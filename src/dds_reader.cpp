#include "dds_reader.h"
#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace dspf {

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

DspfFile parseDDS(const std::string& filename, const std::string& basename) {
    std::ifstream in(filename);
    if (!in.is_open())
        throw std::runtime_error("cannot open DDS file: " + filename);

    DspfFile file;
    file.name = basename;

    std::string line;

    while (std::getline(in, line)) {
        // Pad line to at least 80 chars for safe column access
        while ((int)line.size() < 80) line += ' ';

        // Col 5 (0-based) = form type; col 6 = '*' means comment
        char formType = (char)toupper((unsigned char)line[5]);
        if (formType != 'A') continue;
        if (line.size() > 6 && line[6] == '*') continue;

        // Col 16 (0-based) = name type indicator
        char nameType = (char)toupper((unsigned char)line[16]);

        if (nameType == 'R') {
            // Record format: name at cols 18-27 (0-based)
            std::string recname = toUpper(trim(cols(line, 18, 28)));
            if (recname.empty()) continue;
            DspfRecord rec;
            rec.name = recname;
            // Check keywords in functions area (cols 44+)
            std::string funcs = cols(line, 44, 80);
            for (auto& kw : parseKeywords(funcs)) {
                if (kw == "SFL") {
                    rec.recType = RecType::SFL;
                } else if (kw.rfind("SFLCTL(", 0) == 0) {
                    rec.recType    = RecType::SFLCTL;
                    rec.sflCtlFor  = kw.substr(7, kw.size() - 8);
                } else if (kw.rfind("SFLPAG(", 0) == 0) {
                    rec.sflPag = parseNum(kw.substr(7, kw.size() - 8));
                } else if (kw.rfind("SFLSIZ(", 0) == 0) {
                    rec.sflSiz = parseNum(kw.substr(7, kw.size() - 8));
                } else if (kw.rfind("TEXT(", 0) == 0) {
                    std::string inner = kw.substr(5, kw.size() - 6);
                    rec.title = stripQuotes(inner);
                } else {
                    std::string keyName; int ind;
                    if (parseCFCA(kw, keyName, ind)) {
                        DspfKey k; k.key = keyName; k.indicator = ind;
                        rec.keys.push_back(std::move(k));
                    } else {
                        // Record-level runtime keywords
                        static const char* const recRtKws[] = {
                            "PROTECT", "OVERLAY", "NOCLEAR", "ALARM", "NOINPUT", nullptr
                        };
                        for (int ri = 0; recRtKws[ri]; ri++) {
                            size_t klen = strlen(recRtKws[ri]);
                            if (kw.rfind(recRtKws[ri], 0) == 0 &&
                                (kw.size() == klen || kw[klen] == '(')) {
                                rec.keywords.push_back(kw);
                                break;
                            }
                        }
                    }
                }
            }
            file.records.push_back(std::move(rec));

        } else {
            if (file.records.empty()) continue;

            // Parse option indicator from cols 7-9 (0-based) → COND keyword
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

            std::string fieldname = toUpper(trim(cols(line, 16, 26)));
            std::string lenstr    = trim(cols(line, 29, 34));
            char dtype            = (char)toupper((unsigned char)line[34]);
            std::string decstr    = trim(cols(line, 35, 37));
            char usage            = (char)toupper((unsigned char)line[37]);
            int  row              = parseNum(cols(line, 38, 41));
            int  col              = parseNum(cols(line, 41, 44));
            std::string funcs     = cols(line, 44, 80);

            // Keyword-only lines (no field name, no position): SFLPAG, SFLSIZ, etc.
            if (row == 0 && col == 0 && fieldname.empty()) {
                for (auto& kw : parseKeywords(funcs)) {
                    if (kw.rfind("SFLPAG(", 0) == 0)
                        file.records.back().sflPag = parseNum(kw.substr(7, kw.size()-8));
                    else if (kw.rfind("SFLSIZ(", 0) == 0)
                        file.records.back().sflSiz = parseNum(kw.substr(7, kw.size()-8));
                    else {
                        std::string keyName; int ind;
                        if (parseCFCA(kw, keyName, ind)) {
                            DspfKey k; k.key = keyName; k.indicator = ind;
                            file.records.back().keys.push_back(std::move(k));
                        } else {
                            static const char* const recRtKws[] = {
                                "PROTECT", "OVERLAY", "NOCLEAR", "ALARM", "NOINPUT", nullptr
                            };
                            for (int ri = 0; recRtKws[ri]; ri++) {
                                size_t klen = strlen(recRtKws[ri]);
                                if (kw.rfind(recRtKws[ri], 0) == 0 &&
                                    (kw.size() == klen || kw[klen] == '(')) {
                                    file.records.back().keywords.push_back(kw);
                                    break;
                                }
                            }
                        }
                    }
                }
                continue;
            }

            if (!fieldname.empty() && !lenstr.empty()) {
                // Data field
                DspfField f;
                f.name  = fieldname;
                f.dtype = (dtype == 'S' || dtype == 'P' || dtype == 'B' || dtype == 'F') ? dtype : 'A';
                f.len   = parseNum(lenstr);
                f.dec   = parseNum(decstr);
                f.io    = (usage == 'I' || usage == 'O' || usage == 'B' || usage == 'H') ? usage : 'O';
                f.row   = row;
                f.col   = col;
                f.keywords = parseKeywords(funcs);
                if (!condKw.empty()) f.keywords.push_back(condKw);
                file.records.back().fields.push_back(std::move(f));
            } else if (row > 0 && col > 0) {
                // Literal: text appears in functions area as a quoted string
                std::string literalText;
                std::vector<std::string> litKws;
                for (auto& kw : parseKeywords(funcs)) {
                    if (!kw.empty() && kw.front() == '\'') {
                        if (literalText.empty()) literalText = stripQuotes(kw);
                    } else {
                        litKws.push_back(kw);
                    }
                }
                if (!condKw.empty()) litKws.push_back(condKw);
                if (!literalText.empty()) {
                    DspfLiteral lit;
                    lit.row      = row;
                    lit.col      = col;
                    lit.text     = literalText;
                    lit.keywords = std::move(litKws);
                    file.records.back().literals.push_back(std::move(lit));
                }
            }
        }
    }

    return file;
}

} // namespace dspf
