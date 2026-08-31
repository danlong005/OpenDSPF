#include "dds_reader.h"
#include <algorithm>
#include <cctype>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
#include <stdexcept>

namespace dspf {

// Record-level keyword name, stripped of any "(...)" parameter list.
static std::string keywordName(const std::string& kw) {
    size_t lp = kw.find('(');
    return lp == std::string::npos ? kw : kw.substr(0, lp);
}

static void warnUnknownKeyword(const std::string& filename, int lineNum,
                                const std::string& recName, const std::string& kw) {
    std::cerr << "dspfc: warning: " << filename << ":" << lineNum
              << ": unrecognized keyword " << keywordName(kw)
              << " on record " << recName << " — ignored\n";
}

// Zero-based column extraction (end is exclusive, clamped to line length)
static std::string cols(const std::string& line, int start, int end) {
    if (start >= (int)line.size()) return "";
    int e = std::min(end, (int)line.size());
    return line.substr(start, e - start);
}

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t");
    return s.substr(a, b - a + 1);
}

static std::string toUpper(std::string s) {
    for (auto& c : s) c = (char)toupper((unsigned char)c);
    return s;
}

static int parseNum(const std::string& s) {
    std::string t = trim(s);
    if (t.empty()) return 0;
    try { return std::stoi(t); } catch (...) { return 0; }
}

// Parse 'TEXT' → TEXT (strips surrounding single quotes)
static std::string stripQuotes(const std::string& s) {
    std::string t = trim(s);
    if (t.size() >= 2 && t.front() == '\'' && t.back() == '\'') {
        std::string inner;
        for (size_t i = 1; i < t.size() - 1; i++) {
            if (t[i] == '\'' && i + 1 < t.size() - 1 && t[i+1] == '\'') {
                inner += '\''; i++;
            } else {
                inner += t[i];
            }
        }
        return inner;
    }
    return t;
}

// Uppercase a keyword string but preserve content inside single quotes.
static std::string upperKw(const std::string& s) {
    std::string r;
    bool inQ = false;
    for (size_t i = 0; i < s.size(); i++) {
        if (!inQ && s[i] == '\'') { inQ = true;  r += s[i]; }
        else if (inQ && s[i] == '\'' && i+1 < s.size() && s[i+1] == '\'') {
            r += "''"; i++;  // escaped quote inside string
        }
        else if (inQ && s[i] == '\'') { inQ = false; r += s[i]; }
        else if (!inQ) { r += (char)toupper((unsigned char)s[i]); }
        else            { r += s[i]; }
    }
    return r;
}

// Parse CFnn(ind) or CAnn(ind) — display file function key keyword.
// Returns true and fills keyName ("F3", "F12", etc.) and indicator.
static bool parseCFCA(const std::string& kw, std::string& keyName, int& indicator) {
    if (kw.size() < 4) return false;
    if (kw[0] != 'C' || (kw[1] != 'F' && kw[1] != 'A')) return false;
    size_t p = 2;
    while (p < kw.size() && isdigit((unsigned char)kw[p])) p++;
    if (p == 2) return false;
    int keyNum = parseNum(kw.substr(2, p - 2));
    if (keyNum < 1 || keyNum > 24) return false;
    keyName = "F" + std::to_string(keyNum);
    indicator = keyNum; // default: indicator == key number
    if (p < kw.size() && kw[p] == '(') {
        size_t q = p + 1;
        while (q < kw.size() && kw[q] == ' ') q++;
        if (q < kw.size() && isdigit((unsigned char)kw[q])) {
            size_t r = q;
            while (r < kw.size() && isdigit((unsigned char)kw[r])) r++;
            indicator = parseNum(kw.substr(q, r - q));
        }
    }
    return true;
}

// Parse ROLLUP(ind)/ROLLDOWN(ind) — display file page-key keywords. Real
// DDS naming is inverted from the physical key: ROLLUP means the content
// rolls up the screen, which happens when the operator presses Page Down;
// ROLLDOWN is Page Up. Maps to the same "PAGEUP"/"PAGEDOWN" key names the
// free-format parser stores for `KEY PAGEUP`/`KEY PAGEDOWN`.
static bool parseRollKw(const std::string& kw, std::string& keyName, int& indicator) {
    bool isUp;
    size_t prefixLen;
    if (kw.rfind("ROLLUP", 0) == 0)        { isUp = true;  prefixLen = 6; }
    else if (kw.rfind("ROLLDOWN", 0) == 0) { isUp = false; prefixLen = 8; }
    else return false;
    if (prefixLen >= kw.size() || kw[prefixLen] != '(') return false;
    size_t q = prefixLen + 1;
    while (q < kw.size() && kw[q] == ' ') q++;
    if (q >= kw.size() || !isdigit((unsigned char)kw[q])) return false;
    size_t r = q;
    while (r < kw.size() && isdigit((unsigned char)kw[r])) r++;
    indicator = parseNum(kw.substr(q, r - q));
    keyName = isUp ? "PAGEDOWN" : "PAGEUP";
    return true;
}

// Parse keyword string at cols 44+ (0-based) e.g. "COLOR(RED) DSPATR(HI) TEXT('foo')"
static std::vector<std::string> parseKeywords(const std::string& kwstr) {
    std::vector<std::string> result;
    std::string s = trim(kwstr);
    size_t i = 0;
    while (i < s.size()) {
        // skip leading space
        while (i < s.size() && s[i] == ' ') i++;
        if (i >= s.size()) break;

        // Check if it's a quoted literal (field constant)
        if (s[i] == '\'') {
            size_t j = i + 1;
            while (j < s.size()) {
                if (s[j] == '\'' && j + 1 < s.size() && s[j+1] == '\'') { j += 2; }
                else if (s[j] == '\'') { j++; break; }
                else j++;
            }
            result.push_back(s.substr(i, j - i));
            i = j;
            continue;
        }

        // Read a keyword token
        size_t start = i;
        while (i < s.size() && s[i] != ' ' && s[i] != '(') i++;
        std::string kw = s.substr(start, i - start);
        if (i < s.size() && s[i] == '(') {
            // Read to matching close paren (handles nested parens minimally)
            size_t depth = 0;
            size_t j = i;
            while (j < s.size()) {
                if (s[j] == '(') depth++;
                else if (s[j] == ')') { if (--depth == 0) { j++; break; } }
                j++;
            }
            kw += s.substr(i, j - i);
            i = j;
        }
        if (!kw.empty()) result.push_back(upperKw(kw));
    }
    return result;
}

// Parse WINDOW(row col height width) — DDS window keyword.
static void applyWindowKw(DspfRecord& rec, const std::string& kw) {
    size_t lp = kw.find('(');
    size_t rp = kw.rfind(')');
    if (lp == std::string::npos || rp == std::string::npos || rp <= lp) return;
    std::istringstream iss(kw.substr(lp + 1, rp - lp - 1));
    int r = 0, c = 0, h = 0, w = 0;
    iss >> r >> c >> h >> w;
    rec.winRow = r; rec.winCol = c; rec.winHeight = h; rec.winWidth = w;
}

// Parse WDWBORDER((*CHAR 'xxxxxxxx') (*COLOR color) (*DSPATR attr)) — the
// three parameter groups are optional and order-independent, matching the
// free-format grammar (parser.y wdwborder_param).
static void applyWdwBorderKw(DspfRecord& rec, const std::string& kw) {
    size_t lp = kw.find('(');
    size_t rp = kw.rfind(')');
    if (lp == std::string::npos || rp == std::string::npos || rp <= lp) return;
    std::string inner = kw.substr(lp + 1, rp - lp - 1);
    size_t i = 0;
    while (i < inner.size()) {
        while (i < inner.size() && inner[i] == ' ') i++;
        if (i >= inner.size() || inner[i] != '(') break;
        size_t depth = 0, j = i;
        while (j < inner.size()) {
            if (inner[j] == '(') depth++;
            else if (inner[j] == ')') { if (--depth == 0) { j++; break; } }
            j++;
        }
        std::string g = trim(inner.substr(i + 1, j - i - 2));
        if (g.rfind("*CHAR", 0) == 0) {
            rec.wdwBorderChars = stripQuotes(trim(g.substr(5)));
        } else if (g.rfind("*COLOR", 0) == 0) {
            rec.wdwBorderColor = trim(g.substr(6));
        } else if (g.rfind("*DSPATR", 0) == 0) {
            rec.wdwBorderAttr = trim(g.substr(7));
        }
        i = j;
    }
}

// ---------------------------------------------------------------------------
// Specification lines
// ---------------------------------------------------------------------------

// A DDS specification line: form type 'A' in position 6, and position 7 not
// '*' (comment). Everything else in the source — blank lines, comments,
// other form types — is skipped, including when scanning for the next line
// of a continued entry.
static bool isSpecLine(const std::string& line) {
    return (char)toupper((unsigned char)line[5]) == 'A' && line[6] != '*';
}

static std::string rtrim(const std::string& s) {
    size_t b = s.find_last_not_of(" \t");
    return b == std::string::npos ? "" : s.substr(0, b + 1);
}

static std::string ltrim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t");
    return a == std::string::npos ? "" : s.substr(a);
}

// Gather the functions area (positions 45-80) of the specification beginning
// at lines[i], following DDS keyword continuation.
//
// A '+' or '-' in the last non-blank position of the functions area means the
// entry continues on the next specification line: '+' resumes at that line's
// first non-blank position, '-' resumes at position 45 exactly, blanks
// included. Text before the continuation character is kept verbatim — its
// trailing blanks are part of the value, which is what makes
//
//     ERRMSG('CUSTOMER ALREADY ON +
//     FILE' 51)
//
// join as "CUSTOMER ALREADY ON FILE" and not "CUSTOMER ALREADY ONFILE".
//
// `i` is advanced to the last physical line consumed, so the caller's loop
// resumes after the whole continued entry. A continuation character with no
// following specification line is left as-is rather than diagnosed: the
// keyword it belongs to will fail to parse on its own terms.
static std::string gatherFuncs(const std::vector<std::string>& lines, size_t& i) {
    std::string funcs = cols(lines[i], 44, 80);
    for (;;) {
        std::string t = rtrim(funcs);
        if (t.empty() || (t.back() != '+' && t.back() != '-')) return funcs;

        size_t j = i + 1;
        while (j < lines.size() && !isSpecLine(lines[j])) j++;
        if (j >= lines.size()) return funcs;

        char cont = t.back();
        funcs = t.substr(0, t.size() - 1);
        std::string next = cols(lines[j], 44, 80);
        funcs += (cont == '+') ? ltrim(next) : next;
        i = j;
    }
}

// Apply one keyword in a record-level context — the record-format line
// itself, or a keyword-only line before the record's first field or
// constant. Both paths went through separate, subtly different copies of
// this before; TEXT() in particular was honoured on the R line and reported
// as unrecognized on a following keyword line.
static void applyRecordKeyword(DspfRecord& rec, const std::string& kw,
                               const std::string& filename, int lineNum) {
    if (kw == "SFL") {
        rec.recType = RecType::SFL;
    } else if (kw.rfind("SFLCTL(", 0) == 0) {
        rec.recType   = RecType::SFLCTL;
        rec.sflCtlFor = kw.substr(7, kw.size() - 8);
    } else if (kw.rfind("SFLPAG(", 0) == 0) {
        rec.sflPag = parseNum(kw.substr(7, kw.size() - 8));
    } else if (kw.rfind("SFLSIZ(", 0) == 0) {
        rec.sflSiz = parseNum(kw.substr(7, kw.size() - 8));
    } else if (kw.rfind("TEXT(", 0) == 0) {
        rec.title = stripQuotes(kw.substr(5, kw.size() - 6));
    } else if (kw.rfind("WINDOW(", 0) == 0) {
        applyWindowKw(rec, kw);
    } else if (kw.rfind("WDWBORDER(", 0) == 0) {
        applyWdwBorderKw(rec, kw);
    } else {
        std::string keyName; int ind;
        if (parseCFCA(kw, keyName, ind) || parseRollKw(kw, keyName, ind)) {
            DspfKey k; k.key = keyName; k.indicator = ind;
            rec.keys.push_back(std::move(k));
            return;
        }
        static const char* const recRtKws[] = {
            "PROTECT", "OVERLAY", "NOCLEAR", "ALARM", "NOINPUT",
            "ERRSFL", "SFLMSGRCD", "CLRL", "CHANGE", "SFLNXTCHG", "INDTXT", nullptr
        };
        for (int ri = 0; recRtKws[ri]; ri++) {
            size_t klen = strlen(recRtKws[ri]);
            if (kw.rfind(recRtKws[ri], 0) == 0 &&
                (kw.size() == klen || kw[klen] == '(')) {
                rec.keywords.push_back(kw);
                return;
            }
        }
        warnUnknownKeyword(filename, lineNum, rec.name, kw);
    }
}

// Apply one keyword appearing before the first record format — the file-level
// keyword area. Every line there used to be skipped outright, so INDARA, REF,
// PRINT and CHGINPDFT all vanished without a word.
//
// Command and page keys collect into `fileKeys` rather than being applied
// here: they belong to every record format in the file, and no record has
// been read yet at this point. They are merged in once parsing is done.
static void applyFileKeyword(DspfFile& file, std::vector<DspfKey>& fileKeys,
                             const std::string& kw,
                             const std::string& filename, int lineNum) {
    if (kw == "INDARA") {
        file.indara = true;
        return;
    }
    std::string keyName; int ind;
    if (parseCFCA(kw, keyName, ind) || parseRollKw(kw, keyName, ind)) {
        DspfKey k; k.key = keyName; k.indicator = ind;
        fileKeys.push_back(std::move(k));
        return;
    }

    // Say which kind of "no" this is. A keyword this compiler knows and has
    // decided against is a different fact from one it does not recognize,
    // and reporting both as "unrecognized" invites someone to go looking for
    // the switch that turns it on.
    struct KnownKw { const char* name; const char* why; };
    static const KnownKw known[] = {
        { "REF",       "names an IBM i database file, which does not exist where "
                       "dspfc runs; write the field definitions out (see TODO.md)" },
        { "REFFLD",    "names an IBM i database file, which does not exist where "
                       "dspfc runs; write the field definitions out (see TODO.md)" },
        { "PRINT",     "enables the Print key, which prints the screen to a printer "
                       "file; this toolchain has no printer output at all" },
        { "CHGINPDFT", "sets default display attributes for input-capable fields; "
                       "recognized, not yet implemented" },
        { nullptr, nullptr }
    };
    std::string name = keywordName(kw);
    for (int i = 0; known[i].name; i++) {
        if (name == known[i].name) {
            std::cerr << "dspfc: warning: " << filename << ":" << lineNum
                      << ": file-level " << name << " is not supported — "
                      << known[i].why << "; ignored\n";
            return;
        }
    }
    std::cerr << "dspfc: warning: " << filename << ":" << lineNum
              << ": unrecognized file-level keyword " << name << " — ignored\n";
}

DspfFile parseDDS(const std::string& filename, const std::string& basename) {
    std::ifstream in(filename);
    if (!in.is_open())
        throw std::runtime_error("cannot open DDS file: " + filename);

    // The whole source is read up front rather than streamed, because a
    // continued entry has to look ahead to the lines that finish it.
    std::vector<std::string> lines;
    {
        std::string line;
        while (std::getline(in, line)) {
            // Tolerate CRLF-terminated source (common when DDS is authored or
            // transferred via Windows) — getline only splits on '\n', so a
            // trailing '\r' would otherwise land inside the padded column data.
            if (!line.empty() && line.back() == '\r') line.pop_back();
            // Pad to at least 80 chars for safe column access
            while ((int)line.size() < 80) line += ' ';
            lines.push_back(std::move(line));
        }
    }

    DspfFile file;
    file.name = basename;
    int errors = 0;

    // Command and page keys from the file-level keyword area, applied to
    // every record format once they are all read.
    std::vector<DspfKey> fileKeys;

    auto error = [&](size_t idx, const std::string& msg) {
        std::cerr << "dspfc: error: " << filename << ":" << (idx + 1)
                  << ": " << msg << "\n";
        errors++;
    };

    // Which entry a following keyword-only line continues. Real DDS scopes
    // keyword lines to the last thing named: before a record's first field or
    // constant they are record-level, after one they extend that field's or
    // constant's own keyword list. Reset at each new record format.
    enum class LastDef { NONE, FIELD, LITERAL };
    LastDef lastDef = LastDef::NONE;

    for (size_t idx = 0; idx < lines.size(); idx++) {
        if (!isSpecLine(lines[idx])) continue;
        const std::string& line = lines[idx];
        int lineNum = (int)idx + 1;

        // Position 17 = name type; position 18 is reserved and must be blank.
        // Only 'R' (record format) and blank (field, constant, or keyword-only
        // line) are meaningful for a display file. Reading anything else as a
        // name is how a misaligned line silently becomes a different entry, so
        // it is refused rather than guessed at.
        char nameType = (char)toupper((unsigned char)line[16]);
        if (nameType != ' ' && nameType != 'R') {
            error(idx, std::string("position 17 (name type) is '") + line[16] +
                       "' — expected 'R' for a record format or blank for a field, "
                       "constant or keyword line. Names start in position 19.");
            continue;
        }
        if (line[17] != ' ') {
            error(idx, std::string("position 18 is '") + line[17] +
                       "' — that position is reserved and must be blank. "
                       "Names start in position 19.");
            continue;
        }

        // Gather the functions area first: a continued entry may span several
        // physical lines, and idx must advance past all of them either way.
        size_t lastLine = idx;
        std::string funcs = gatherFuncs(lines, lastLine);

        if (nameType == 'R') {
            std::string recname = toUpper(trim(cols(line, 18, 28)));
            if (recname.empty()) { idx = lastLine; continue; }
            DspfRecord rec;
            rec.name = recname;
            for (auto& kw : parseKeywords(funcs))
                applyRecordKeyword(rec, kw, filename, lineNum);
            file.records.push_back(std::move(rec));
            lastDef = LastDef::NONE;
            idx = lastLine;
            continue;
        }

        // Before the first record format: the file-level keyword area.
        if (file.records.empty()) {
            for (auto& kw : parseKeywords(funcs))
                applyFileKeyword(file, fileKeys, kw, filename, lineNum);
            idx = lastLine;
            continue;
        }
        DspfRecord& rec = file.records.back();

        // Option indicator in positions 8-10 → COND keyword
        std::string condKw;
        {
            std::string opt = trim(cols(line, 7, 10));
            if (!opt.empty() && (isdigit((unsigned char)opt[0]) ||
                                 opt[0]=='N' || opt[0]=='n')) {
                bool neg = (opt[0]=='N' || opt[0]=='n');
                std::string digits = trim(neg ? opt.substr(1) : opt);
                if (digits.size() >= 2 && isdigit((unsigned char)digits[0])) {
                    condKw = std::string(neg ? "COND(N*IN" : "COND(*IN")
                             + digits.substr(0,2) + ")";
                }
            }
        }

        std::string fieldname = toUpper(trim(cols(line, 18, 28)));
        char refMark          = (char)toupper((unsigned char)line[28]);
        std::string lenstr    = trim(cols(line, 29, 34));
        char dtype            = (char)toupper((unsigned char)line[34]);
        std::string decstr    = trim(cols(line, 35, 37));
        char usage            = (char)toupper((unsigned char)line[37]);
        int  row              = parseNum(cols(line, 38, 41));
        int  col              = parseNum(cols(line, 41, 44));

        // Keyword-only line: no name, no position. Belongs to the last field
        // or constant of this record if there is one, otherwise to the record.
        if (row == 0 && col == 0 && fieldname.empty()) {
            std::vector<std::string>* target = nullptr;
            if (lastDef == LastDef::FIELD && !rec.fields.empty())
                target = &rec.fields.back().keywords;
            else if (lastDef == LastDef::LITERAL && !rec.literals.empty())
                target = &rec.literals.back().keywords;

            // A conditioning indicator here conditions the individual
            // keywords on this line. Conditions are modelled per entry (a
            // COND() in the field's or constant's own keyword list), not per
            // keyword, so applying it would condition the whole entry — a
            // different thing. Reported rather than silently taken either way.
            if (!condKw.empty()) {
                std::cerr << "dspfc: warning: " << filename << ":" << lineNum
                          << ": record " << rec.name << ": option indicator on a "
                          << "keyword line conditions those keywords individually, "
                          << "which is not modelled — keywords kept, "
                          << condKw << " dropped\n";
            }

            for (auto& kw : parseKeywords(funcs)) {
                if (target) target->push_back(kw);
                else        applyRecordKeyword(rec, kw, filename, lineNum);
            }
            idx = lastLine;
            continue;
        }

        // Position 29 is the Reference column, its own entry immediately
        // before Length (30-34) — not the first digit of the length. It holds
        // 'R' when the field takes its length and type from the file named by
        // the file-level REF/REFFLD keywords.
        //
        // Resolving that is a deliberate non-goal, not a gap: the reference
        // names an IBM i database *FILE object and reads the definitions out
        // of the object itself. dspfc compiles one source file standalone,
        // with no database, no catalog and no IBM i, so there is nothing for
        // the reference to denote. Refused outright rather than guessed at —
        // a guessed length puts the field on screen at the wrong width.
        if (refMark == 'R') {
            error(idx, "field " + fieldname + " is defined by reference ('R' in "
                       "position 29) — REF/REFFLD names an IBM i database file "
                       "and is not supported; declare the field's length and "
                       "data type here instead");
            idx = lastLine;
            continue;
        }

        // DDS conventionally leaves the length column blank for L/T/Z
        // fields (length is implied by the *ISO default format), so the
        // field-vs-literal test below can't require lenstr like it does
        // for every other type.
        bool isDateTimeType = (dtype == 'L' || dtype == 'T' || dtype == 'Z');
        if (!fieldname.empty() && (!lenstr.empty() || isDateTimeType)) {
            // Data field
            DspfField f;
            f.name  = fieldname;
            f.dtype = (dtype == 'S' || dtype == 'P' || dtype == 'B' || dtype == 'F' ||
                       dtype == 'L' || dtype == 'T' || dtype == 'Z') ? dtype : 'A';
            f.len   = lenstr.empty() ? 0 : parseNum(lenstr);
            if (f.len == 0 && isDateTimeType) {
                // *ISO default lengths: date=10 (YYYY-MM-DD), time=8
                // (HH.MM.SS), timestamp=26 (YYYY-MM-DD-HH.MM.SS.NNNNNN).
                f.len = (dtype == 'L') ? 10 : (dtype == 'T') ? 8 : 26;
            }
            f.dec   = parseNum(decstr);
            f.io    = (usage == 'I' || usage == 'O' || usage == 'B' || usage == 'H') ? usage : 'O';
            f.row   = row;
            f.col   = col;
            f.keywords = parseKeywords(funcs);
            if (!condKw.empty()) f.keywords.push_back(condKw);
            rec.fields.push_back(std::move(f));
            lastDef = LastDef::FIELD;
        } else if (row > 0 && col > 0) {
            // Constant: the text appears in the functions area as a quoted
            // string. DDS also allows DATE, TIME, USER, SYSNAME and MSGCON
            // constants there; none are supported, so a positioned line that
            // yields no quoted text is reported rather than dropped.
            std::string literalText;
            std::vector<std::string> litKws;
            bool haveText = false;
            for (auto& kw : parseKeywords(funcs)) {
                if (!kw.empty() && kw.front() == '\'') {
                    if (!haveText) { literalText = stripQuotes(kw); haveText = true; }
                } else {
                    litKws.push_back(kw);
                }
            }
            if (!condKw.empty()) litKws.push_back(condKw);
            if (haveText) {
                DspfLiteral lit;
                lit.row      = row;
                lit.col      = col;
                lit.text     = literalText;
                lit.keywords = std::move(litKws);
                rec.literals.push_back(std::move(lit));
                lastDef = LastDef::LITERAL;
            } else {
                std::cerr << "dspfc: warning: " << filename << ":" << lineNum
                          << ": record " << rec.name << ": constant at row " << row
                          << " col " << col << " has no quoted text ("
                          << trim(funcs) << ") — ignored\n";
            }
        }

        idx = lastLine;
    }

    // File-level command and page keys apply to every record format in the
    // file. A record that declares the same key names its own indicator for
    // it and wins, so merge only the keys a record has not spoken for —
    // matching DDS, where a record-level keyword overrides the file-level one
    // of the same name. Merged after the whole source is read, since a
    // record's own keys arrive on lines following its R line and are not all
    // present when the record is first pushed.
    for (auto& rec : file.records) {
        for (const auto& fk : fileKeys) {
            bool declared = false;
            for (const auto& rk : rec.keys)
                if (rk.key == fk.key) { declared = true; break; }
            if (!declared) rec.keys.push_back(fk);
        }
    }

    if (errors > 0)
        throw std::runtime_error(std::to_string(errors) + " error(s) — aborting");

    return file;
}

} // namespace dspf
