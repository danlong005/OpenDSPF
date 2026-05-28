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
        if (!kw.empty()) result.push_back(toUpper(kw));
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
            // Check for TEXT keyword in functions area
            std::string funcs = cols(line, 44, 80);
            for (auto& kw : parseKeywords(funcs)) {
                if (kw.rfind("TEXT(", 0) == 0) {
                    std::string inner = kw.substr(5, kw.size() - 6);
                    rec.title = stripQuotes(inner);
                }
            }
            file.records.push_back(std::move(rec));

        } else if (nameType == 'K') {
            // Key definition: key name at cols 18+
            std::string keyname = toUpper(trim(cols(line, 18, 28)));
            if (file.records.empty() || keyname.empty()) continue;
            DspfKey k;
            k.key = keyname;
            k.indicator = 0;
            // Check for IND keyword
            std::string funcs = cols(line, 44, 80);
            for (auto& kw : parseKeywords(funcs)) {
                if (kw.rfind("IND(", 0) == 0 || kw.rfind("INDICATOR(", 0) == 0) {
                    size_t p = kw.find('(');
                    if (p != std::string::npos) {
                        k.indicator = parseNum(kw.substr(p + 1, kw.size() - p - 2));
                    }
                }
            }
            // Infer indicator from key name: F3 → 03, F12 → 12, etc.
            if (k.indicator == 0 && keyname.size() >= 2 && keyname[0] == 'F') {
                try { k.indicator = std::stoi(keyname.substr(1)); } catch (...) {}
                // Map F1-F9 → indicators 01-09, F10-F12 → 10-12, etc.
                // Clamp to valid range
                if (k.indicator < 1 || k.indicator > 99) k.indicator = 0;
            }
            file.records.back().keys.push_back(std::move(k));

        } else {
            if (file.records.empty()) continue;

            std::string fieldname = toUpper(trim(cols(line, 16, 26)));
            std::string lenstr    = trim(cols(line, 29, 34));
            char dtype            = (char)toupper((unsigned char)line[34]);
            std::string decstr    = trim(cols(line, 35, 37));
            char usage            = (char)toupper((unsigned char)line[37]);
            int  row              = parseNum(cols(line, 38, 41));
            int  col              = parseNum(cols(line, 41, 44));
            std::string funcs     = cols(line, 44, 80);

            if (row == 0 && col == 0 && fieldname.empty()) continue;

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
                file.records.back().fields.push_back(std::move(f));
            } else if (row > 0 && col > 0) {
                // Literal: text appears in functions area as a quoted string
                std::string literalText;
                for (auto& kw : parseKeywords(funcs)) {
                    if (!kw.empty() && kw.front() == '\'') {
                        literalText = stripQuotes(kw);
                        break;
                    }
                }
                if (!literalText.empty()) {
                    DspfLiteral lit;
                    lit.row  = row;
                    lit.col  = col;
                    lit.text = literalText;
                    file.records.back().literals.push_back(std::move(lit));
                }
            }
        }
    }

    return file;
}

} // namespace dspf
