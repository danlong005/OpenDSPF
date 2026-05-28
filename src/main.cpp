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
        if (tl.rfind("**DSPF", 0) == 0 || tl.rfind("**dspf", 0) == 0) return SrcFormat::FREE;
        if (line.size() > 5 && (line[5] == 'A' || line[5] == 'a')) return SrcFormat::DDS;
        return SrcFormat::UNKNOWN;
    }
    return SrcFormat::UNKNOWN;
}

static void writeFile(const std::string& path, const std::string& content) {
    std::ofstream out(path);
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
        std::cerr << "dspfc: cannot determine source format (expected **DSPF header or DDS A-specs)\n";
        return 1;
    }

    std::string base = basename_noext(infile);
    dspf::DspfFile fileAst;
    fileAst.name = base;

    if (fmt == SrcFormat::DDS) {
        std::cout << "dspfc: reading DDS A-spec source: " << infile << "\n";
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

    std::cout << "dspfc: " << fileAst.records.size() << " record format(s) found\n";

    std::string jsonPath   = outdir + "/" + base + ".dspfd";
    std::string headerPath = outdir + "/" + base + "_dspf.h";

    writeFile(jsonPath,   dspf::emitJSON(fileAst));
    writeFile(headerPath, dspf::emitHeader(fileAst));

    return 0;
}
