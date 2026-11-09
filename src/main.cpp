#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include "ast.h"
#include "codegen.h"
#include "dds_reader.h"
#include "json_reader.h"

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
// If it starts with '{' → a display file defined in JSON (json_reader.h).
enum class SrcFormat { FREE, DDS, JSON, UNKNOWN };

static SrcFormat detectFormat(const std::string& filename) {
    std::ifstream in(filename);
    if (!in.is_open()) return SrcFormat::UNKNOWN;
    std::string line;
    while (std::getline(in, line)) {
        // Trim leading whitespace for comparison
        std::string tl = line;
        while (!tl.empty() && (tl.front() == ' ' || tl.front() == '\t')) tl.erase(tl.begin());
        if (tl.empty()) continue;
        if (tl[0] == '{') return SrcFormat::JSON;
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
// A keyword as stored, minus the "*INnn?" / "N*INnn?" prefix the DDS reader
// gives a keyword conditioned by its own option indicator.
static std::string bareKeyword(const std::string& kw, bool* conditioned = nullptr) {
    size_t q = kw.find('?');
    size_t lp = kw.find('(');
    bool c = q != std::string::npos && (lp == std::string::npos || q < lp);
    if (conditioned) *conditioned = c;
    return c ? kw.substr(q + 1) : kw;
}

static std::string keywordNameOf(const std::string& kw) {
    std::string b = bareKeyword(kw);
    return b.substr(0, b.find('('));
}

static std::string keywordParams(const std::string& kw) {
    std::string b = bareKeyword(kw);
    size_t lp = b.find('(');
    if (lp == std::string::npos || b.back() != ')') return "";
    return b.substr(lp + 1, b.size() - lp - 2);
}

// The value the system supplies for a constant, or "" for one with text.
static std::string systemValueOf(const dspf::DspfLiteral& lit) {
    for (const auto& k : lit.keywords) {
        std::string n = keywordNameOf(k);
        if (n == "DATE" || n == "TIME" || n == "USER" || n == "SYSNAME") return n;
    }
    return "";
}

// How many positions a constant takes on the screen. A DATE is six digits,
// or eight with *YY, plus two separators under EDTCDE(Y); TIME is hh:mm:ss
// under its default edit word; USER is 10 characters and SYSNAME 8 (IBM's
// DATE, TIME, USER and SYSNAME keyword descriptions).
static int literalWidth(const dspf::DspfLiteral& lit) {
    std::string sv = systemValueOf(lit);
    if (sv.empty()) return (int)lit.text.size();
    if (sv == "USER") return 10;
    if (sv == "SYSNAME") return 8;
    int digits = 6;
    bool edtY = false; int edtwrd = 0;
    for (const auto& k : lit.keywords) {
        std::string n = keywordNameOf(k), p = keywordParams(k);
        if (n == "DATE" && p.find("*YY") != std::string::npos) digits = 8;
        if (n == "EDTCDE" && (p == "Y" || p == "y")) edtY = true;
        if (n == "EDTWRD" && p.size() >= 2) edtwrd = (int)p.size() - 2;
    }
    if (edtwrd) return edtwrd;
    if (sv == "TIME") return 8;
    return digits + (edtY ? 2 : 0);
}

// IBM i's rules for a WINDOW record and for COLOR values, checked when the
// display file compiles, as CRTDSPF does (each probed on PUB400).
//   - WINDOW(line pos lines positions) puts the border's top-left corner at
//     (line, pos); line 1 position 1 is not allowed (CPD8173). The border
//     takes a line above and below, and a border plus attribute byte on
//     each side, so line + lines <= screen lines - 1 and pos + positions <=
//     screen positions - 3 (CPD8182).
//   - A window record's fields and literals are placed relative to the
//     window's inside. Its last line is the message line, so they go on
//     lines 1 to lines - 1 (CPD7830), and within positions (CPD8186).
//   - A color is one of the three-letter codes BLU GRN PNK RED TRQ WHT YLW
//     (CPD7494 for GREEN, BLUE, ...).
static bool validateWindowsAndColors(const std::string& infile, const dspf::DspfFile& file) {
    bool ok = true;
    auto fail = [&](const std::string& rec, const std::string& msg) {
        std::cerr << "dspfc: error: " << infile << ": record " << rec << ": " << msg << "\n";
        ok = false;
    };
    static const char* const codes[] = {"BLU", "GRN", "PNK", "RED", "TRQ", "WHT", "YLW", nullptr};
    auto validColor = [](const std::string& c) {
        for (const char* const* k = codes; *k; k++) if (c == *k) return true;
        return false;
    };
    auto checkColors = [&](const std::string& rec, const std::vector<std::string>& kws) {
        for (const auto& k : kws) {
            if (k.rfind("COLOR(", 0) != 0 || k.back() != ')') continue;
            std::string c = k.substr(6, k.size() - 7);
            if (!validColor(c))
                fail(rec, "COLOR(" + c + ") is not a DDS color; use BLU, GRN, PNK, RED, TRQ, "
                     "WHT or YLW (IBM: CPD7494)");
        }
    };
    for (const auto& rec : file.records) {
        checkColors(rec.name, rec.keywords);
        for (const auto& f : rec.fields) checkColors(rec.name, f.keywords);
        for (const auto& l : rec.literals) checkColors(rec.name, l.keywords);
        if (!rec.wdwBorderColor.empty() && !validColor(rec.wdwBorderColor))
            fail(rec.name, "WDWBORDER color " + rec.wdwBorderColor + " is not a DDS color; use "
                 "BLU, GRN, PNK, RED, TRQ, WHT or YLW (IBM: CPD7494)");
        if (rec.winHeight <= 0) continue;
        std::string w = "WINDOW(" + std::to_string(rec.winRow) + " " + std::to_string(rec.winCol) +
                        " " + std::to_string(rec.winHeight) + " " + std::to_string(rec.winWidth) + ")";
        if (rec.winRow == 1 && rec.winCol == 1)
            fail(rec.name, w + ": a window cannot start at line 1, position 1 (IBM: CPD8173)");
        if (rec.winRow < 1 || rec.winCol < 1 ||
            rec.winRow + rec.winHeight > rec.screenRows - 1 ||
            rec.winCol + rec.winWidth > rec.screenCols - 3)
            fail(rec.name, w + " does not fit the " + std::to_string(rec.screenRows) + "x" +
                 std::to_string(rec.screenCols) + " display: its border takes a line above and "
                 "below and two positions each side (IBM: CPD8182)");
        auto inWindow = [&](const std::string& what, int row, int col, int len) {
            if (row < 1 || row > rec.winHeight - 1)
                fail(rec.name, what + " is on line " + std::to_string(row) + " of the window; "
                     "positions in a window record count from its inside, and its last line (" +
                     std::to_string(rec.winHeight) + ") is the message line, so lines 1-" +
                     std::to_string(rec.winHeight - 1) + " are available (IBM: CPD7830)");
            else if (col < 1 || col + len - 1 > rec.winWidth)
                fail(rec.name, what + " at position " + std::to_string(col) + ", length " +
                     std::to_string(len) + ", extends outside the window's " +
                     std::to_string(rec.winWidth) + " positions (IBM: CPD8186)");
        };
        for (const auto& f : rec.fields)
            if (f.io != 'H') inWindow("field " + f.name, f.row, f.col, f.len);
        for (const auto& l : rec.literals)
            inWindow(l.text.empty() ? systemValueOf(l) + " constant"
                                    : "literal '" + l.text.substr(0, 20) + "'",
                     l.row, l.col, literalWidth(l));
    }
    return ok;
}

// ERRMSG / ERRMSGID, and constants the system fills in (DATE, TIME, USER,
// SYSNAME), checked as CRTDSPF checks them. Each rule and message ID below
// was probed with CRTDSPF on PUB400 (2026-11-08).
static bool validateErrmsgAndSystemValues(const std::string& infile, const dspf::DspfFile& file) {
    bool ok = true;
    auto fail = [&](const std::string& rec, const std::string& msg) {
        std::cerr << "dspfc: error: " << infile << ": record " << rec << ": " << msg << "\n";
        ok = false;
    };
    for (const auto& rec : file.records) {
        for (const auto& f : rec.fields) {
            for (const auto& k : f.keywords) {
                std::string n = keywordNameOf(k);
                if (n != "ERRMSG" && n != "ERRMSGID") continue;
                std::string what = n + " on field " + f.name;
                if (rec.recType == dspf::RecType::SFL) {
                    fail(rec.name, what + " is not allowed in a subfile record; IBM i "
                         "displays a subfile's messages with SFLMSG (IBM: CPD7562)");
                    continue;
                }
                if (f.io == 'H') {
                    fail(rec.name, what + " is not allowed on a hidden field, which is "
                         "never displayed (IBM: CPD7552)");
                    continue;
                }
                std::string p = keywordParams(k);
                if (n == "ERRMSG") {
                    // 'message text' [response-indicator]
                    size_t i = 0;
                    bool good = !p.empty() && p[0] == '\'';
                    if (good) {
                        for (i = 1; i < p.size(); i++) {
                            if (p[i] != '\'') continue;
                            if (i + 1 < p.size() && p[i + 1] == '\'') { i++; continue; }
                            break;
                        }
                        good = i < p.size();
                        std::string rest = good ? p.substr(i + 1) : "";
                        size_t a = rest.find_first_not_of(' ');
                        rest = a == std::string::npos ? "" : rest.substr(a);
                        while (!rest.empty() && rest.back() == ' ') rest.pop_back();
                        if (!rest.empty()) {
                            bool digits = rest.size() <= 2 &&
                                rest.find_first_not_of("0123456789") == std::string::npos;
                            good = digits && std::stoi(rest) >= 1;
                        }
                    }
                    if (!good)
                        fail(rec.name, what + ": ERRMSG takes the message text in quotes and "
                             "an optional response indicator, 01-99 (IBM: CPD7516)");
                } else {
                    std::string msgid = p.substr(0, p.find(' '));
                    std::cerr << "dspfc: warning: " << infile << ": record " << rec.name
                              << ": " << what << ": there are no message files where this "
                              << "program runs, so the message identifier " << msgid
                              << " is displayed in place of its text\n";
                }
            }
        }
        for (const auto& lit : rec.literals) {
            std::string label = lit.text.empty() ? "at line " + std::to_string(lit.row) +
                                " position " + std::to_string(lit.col)
                                : "'" + lit.text.substr(0, 20) + "'";
            for (const auto& k : lit.keywords) {
                std::string n = keywordNameOf(k);
                if (n == "ERRMSG" || n == "ERRMSGID")
                    fail(rec.name, n + " on constant " + label + ": an error message belongs "
                         "to a field, not a constant (IBM: CPD7552)");
            }
            std::string sv = systemValueOf(lit);
            if (sv.empty()) continue;
            std::string what = sv + " constant " + label;
            if (!lit.text.empty())
                fail(rec.name, what + " also has quoted text; a constant is either text or "
                     "a value the system supplies, not both (IBM: CPD7577)");
            int systemValues = 0;
            for (const auto& k : lit.keywords) {
                bool conditioned = false;
                std::string bare = bareKeyword(k, &conditioned);
                std::string n = keywordNameOf(k), p = keywordParams(k);
                if (n == "DATE" || n == "TIME" || n == "USER" || n == "SYSNAME") {
                    if (++systemValues == 2)
                        fail(rec.name, what + " also names " + n + "; a constant is one "
                             "of DATE, TIME, USER or SYSNAME");
                    if (n == "DATE") {
                        int job = 0, year = 0; bool bad = false;
                        std::string tok;
                        std::istringstream in(p);
                        while (in >> tok) {
                            if (tok == "*JOB" || tok == "*SYS") job++;
                            else if (tok == "*Y" || tok == "*YY") year++;
                            else bad = true;
                        }
                        if (bad || job > 1 || year > 1)
                            fail(rec.name, what + ": DATE(" + p + ") — DATE takes *JOB or *SYS "
                                 "and *Y or *YY (IBM: CPD7494)");
                    } else if (bare.find('(') != std::string::npos) {
                        fail(rec.name, what + ": " + n + " takes no parameters (IBM: CPD7494)");
                    }
                    if (conditioned)
                        fail(rec.name, what + ": " + n + " cannot be conditioned on its own; "
                             "condition the constant (IBM: CPD7488)");
                    continue;
                }
                if (n == "COND") continue;   // the whole constant's option indicator
                bool allowed = n == "COLOR" || n == "DSPATR" || n == "TEXT" ||
                               ((sv == "DATE" || sv == "TIME") && (n == "EDTCDE" || n == "EDTWRD"));
                if (!allowed) {
                    fail(rec.name, what + ": " + n + " is not allowed with " + sv + "; it takes " +
                         ((sv == "DATE" || sv == "TIME") ? "EDTCDE, EDTWRD, " : "") +
                         "COLOR, DSPATR and TEXT (IBM: CPD7651)");
                } else if (conditioned) {
                    fail(rec.name, what + ": its " + n + " cannot have an option indicator of "
                         "its own; condition the constant instead (IBM: CPD7488)");
                }
            }
        }
    }
    return ok;
}

static void validateFieldBounds(const std::string& infile, const dspf::DspfFile& file) {
    for (const auto& rec : file.records) {
        if (rec.winHeight > 0) continue;   // window positions: validateWindowsAndColors
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
            if (lit.text.empty()) label = systemValueOf(lit);
            checkPos("literal", label, lit.row, lit.col, literalWidth(lit));
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
        std::cerr << "Usage: dspfc <file.dspf|file.dds|file.json> [-o outdir]\n";
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
        std::cerr << "dspfc: cannot determine source format (expected **FREE header, fixed-format A-specs, or a JSON object)\n";
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
    } else if (fmt == SrcFormat::JSON) {
        std::cout << "dspfc: reading JSON display file: " << infile << "\n";
        try {
            fileAst = dspf::parseJSONSource(infile, base);
        } catch (const std::exception& e) {
            std::cerr << "dspfc: error: " << e.what() << "\n";
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
    if (!validateWindowsAndColors(infile, fileAst)) return 1;
    if (!validateErrmsgAndSystemValues(infile, fileAst)) return 1;

    std::cout << "dspfc: " << fileAst.records.size() << " record format(s) found\n";

    std::string jsonPath   = outdir + "/" + base + ".dspfd";
    std::string headerPath = outdir + "/" + base + "_dspf.h";

    writeFile(jsonPath,   dspf::emitJSON(fileAst));
    writeFile(headerPath, dspf::emitHeader(fileAst));

    return 0;
}
