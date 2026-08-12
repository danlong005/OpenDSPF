#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include "ast.h"
#include "codegen.h"
#include "dds_reader.h"

#ifndef DSPFC_VERSION
#define DSPFC_VERSION "dev"
#endif

extern FILE*           yyin;
extern int             yyparse(dspf::DspfFile*);
extern int             dspf_get_error_count();

static std::string    basename_noext(const std::string& path) {
    // Strip directory
    size_t slash = path.find_last_of("/\\");
    std::string base = (slash == std::string::npos) ? path : path.substr(slash + 1);
    // Strip extension
    size_t dot = base.rfind('.');
    if (dot != std::string::npos) base = base.substr(0, dot);
    return base;
}

static std::string    dirof(const std::string& path) {
    size_t slash = path.find_last_of("/\\");
    if (slash == std::string::npos) return ".";
    return path.substr(0, slash);
}

// Detect format: peek at col 5 (0-based) of first non-blank line.
// If it's 'A' → DDS column-based source.
// If line starts with "**DSPF" → free-format.
enum class SrcFormat { FREE, DDS, UNKNOWN };

static SrcFormat detectFormat(const std::string& filename) {
    std::ifstream in(filename);
    if (!in.is_open()) return SrcFormat::UNKNOWN;
    std::string line;
    while (std::getline(in, line)) {
        // Trim leading whitespace for comparison
        std::string tl = line;
        while (!tl.empty() && (tl.front() == ' ' || tl.front() == '\t')) tl.erase(tl.begin());
        if (tl.empty()) continue;
        if (tl.rfind("**FREE", 0) == 0 || tl.rfind("**free", 0) == 0 ||
            tl.rfind("**DSPF", 0) == 0 || tl.rfind("**dspf", 0) == 0) return SrcFormat::FREE;
        if (line.size() > 5 && (line[5] == 'A' || line[5] == 'a')) return SrcFormat::DDS;
        return SrcFormat::UNKNOWN;
    }
    return SrcFormat::UNKNOWN;
}

// Compile-time sanity checks that don't fit cleanly into either format's own
// reader — both run on the fully-parsed, format-agnostic AST, so free- and
// fixed-format source get them for free from the same code.

// SFLPAG must not exceed SFLSIZ: a subfile can't show more rows per page
// than it can ever hold. This is a structurally broken spec (not a
// stylistic issue like an unrecognized keyword), so it's a hard error.
static bool validateSflSizes(const std::string& infile, const dspf::DspfFile& file) {
    bool ok = true;
    for (const auto& rec : file.records) {
        if (rec.recType != dspf::RecType::SFLCTL) continue;
        if (rec.sflPag > 0 && rec.sflSiz > 0 && rec.sflPag > rec.sflSiz) {
            std::cerr << "dspfc: error: " << infile << ": record " << rec.name
                      << ": SFLPAG(" << rec.sflPag << ") exceeds SFLSIZ(" << rec.sflSiz
                      << ") — a subfile can't display more rows per page than it can hold\n";
            ok = false;
        }
    }
    return ok;
}

// Every field/literal position must fit within its record's declared
// SCREEN SIZE, or the runtime will silently render it off-screen (or not
// at all). A warning, not an error — matches unrecognized-keyword
// severity, and a developer should still be able to compile and iterate
// with a temporarily-misplaced field.
static void validateFieldBounds(const std::string& infile, const dspf::DspfFile& file) {
    for (const auto& rec : file.records) {
        auto checkPos = [&](const std::string& what, const std::string& name,
                             int row, int col, int len) {
            if (row < 1 || row > rec.screenRows) {
                std::cerr << "dspfc: warning: " << infile << ": record " << rec.name
                          << ": " << what << " " << name << " row " << row
                          << " is outside SCREEN SIZE(" << rec.screenRows << " "
                          << rec.screenCols << ")\n";
            } else if (col < 1 || col + len - 1 > rec.screenCols) {
                std::cerr << "dspfc: warning: " << infile << ": record " << rec.name
                          << ": " << what << " " << name << " col " << col
                          << " (length " << len << ") extends outside SCREEN SIZE("
                          << rec.screenRows << " " << rec.screenCols << ")\n";
            }
        };
        for (const auto& f : rec.fields) {
            if (f.io == 'H') continue; // never rendered — position is irrelevant
            checkPos("field", f.name, f.row, f.col, f.len);
        }
        for (const auto& lit : rec.literals) {
            std::string label = "'" + lit.text.substr(0, 20)
                                 + (lit.text.size() > 20 ? "..." : "") + "'";
            checkPos("literal", label, lit.row, lit.col, (int)lit.text.size());
        }
    }
}

static void writeFile(const std::string& path, const std::string& content) {
    // Binary mode: on Windows, default (text) mode silently rewrites every
    // '\n' in content to "\r\n", making dspfc's output depend on the host
    // platform. Write the bytes we built exactly as built, everywhere.
    std::ofstream out(path, std::ios::binary);
    if (!out.is_open()) {
        std::cerr << "dspfc: cannot write " << path << "\n";
        return;
    }
    out << content;
    std::cout << "  wrote " << path << "\n";
}

int main(int argc, char* argv[]) {
    if (argc == 2 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0)) {
        std::cout << "dspfc " << DSPFC_VERSION << "\n";
        return 0;
    }
    if (argc < 2) {
        std::cerr << "Usage: dspfc <file.dspf|file.dds> [-o outdir]\n";
        std::cerr << "  -v, --version  Print version and exit\n";
        return 1;
    }

    std::string infile = argv[1];
    std::string outdir = dirof(infile);

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            outdir = argv[++i];
        }
    }

    SrcFormat fmt = detectFormat(infile);
    if (fmt == SrcFormat::UNKNOWN) {
        std::cerr << "dspfc: cannot determine source format (expected **FREE header or fixed-format A-specs)\n";
        return 1;
    }

    std::string base = basename_noext(infile);
    dspf::DspfFile fileAst;
    fileAst.name = base;

    if (fmt == SrcFormat::DDS) {
        std::cout << "dspfc: reading fixed-format DSPF source: " << infile << "\n";
        try {
            fileAst = dspf::parseDDS(infile, base);
        } catch (const std::exception& e) {
            std::cerr << "dspfc: " << e.what() << "\n";
            return 1;
        }
    } else {
        std::cout << "dspfc: reading free-format DSPF source: " << infile << "\n";
        yyin = fopen(infile.c_str(), "r");
        if (!yyin) { std::cerr << "dspfc: cannot open " << infile << "\n"; return 1; }
        yyparse(&fileAst);
        fclose(yyin);
        if (dspf_get_error_count() > 0) {
            std::cerr << "dspfc: " << dspf_get_error_count() << " error(s) — aborting\n";
            return 1;
        }
    }

    if (fileAst.records.empty()) {
        std::cerr << "dspfc: no RECORD definitions found in " << infile << "\n";
        return 1;
    }

    if (!validateSflSizes(infile, fileAst)) {
        return 1;
    }
    validateFieldBounds(infile, fileAst);

    std::cout << "dspfc: " << fileAst.records.size() << " record format(s) found\n";

    std::string jsonPath   = outdir + "/" + base + ".dspfd";
    std::string headerPath = outdir + "/" + base + "_dspf.h";

    writeFile(jsonPath,   dspf::emitJSON(fileAst));
    writeFile(headerPath, dspf::emitHeader(fileAst));

    return 0;
}
