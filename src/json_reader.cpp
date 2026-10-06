#include "json_reader.h"
#include <cctype>
#include <cstring>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace dspf {

namespace {

// ---- A small JSON parser that remembers each value's line ----------------

struct JVal {
    enum Kind { Null, Bool, Num, Str, Arr, Obj } kind = Null;
    int line = 0;
    bool b = false;
    double num = 0;
    bool integral = false;
    std::string str;
    std::vector<JVal> arr;
    std::vector<std::pair<std::string, JVal>> obj;   // in source order

    const JVal* get(const std::string& k) const {
        for (const auto& kv : obj) if (kv.first == k) return &kv.second;
        return nullptr;
    }
};

class Parser {
public:
    Parser(const std::string& src, const std::string& file) : s_(src), file_(file) {}

    JVal parseDocument() {
        JVal v = value();
        ws();
        if (pos_ < s_.size()) fail("unexpected text after the JSON value");
        return v;
    }

private:
    const std::string& s_;
    const std::string& file_;
    size_t pos_ = 0;
    int line_ = 1;

    [[noreturn]] void fail(const std::string& msg) {
        throw std::runtime_error(file_ + ":" + std::to_string(line_) + ": " + msg);
    }
    void ws() {
        while (pos_ < s_.size() && std::isspace((unsigned char)s_[pos_])) {
            if (s_[pos_] == '\n') line_++;
            pos_++;
        }
    }
    bool eat(char c) {
        ws();
        if (pos_ < s_.size() && s_[pos_] == c) { pos_++; return true; }
        return false;
    }
    void expect(char c) {
        if (!eat(c)) fail(std::string("expected '") + c + "'");
    }
    bool word(const char* w) {
        size_t n = std::char_traits<char>::length(w);
        if (s_.compare(pos_, n, w) != 0) return false;
        pos_ += n;
        return true;
    }

    JVal value() {
        ws();
        JVal v;
        v.line = line_;
        if (pos_ >= s_.size()) fail("unexpected end of file");
        char c = s_[pos_];
        if (c == '{') {
            pos_++;
            v.kind = JVal::Obj;
            if (eat('}')) return v;
            do {
                ws();
                if (pos_ >= s_.size() || s_[pos_] != '"') fail("expected a member name in quotes");
                std::string k = string();
                expect(':');
                v.obj.emplace_back(k, value());
            } while (eat(','));
            expect('}');
        } else if (c == '[') {
            pos_++;
            v.kind = JVal::Arr;
            if (eat(']')) return v;
            do { v.arr.push_back(value()); } while (eat(','));
            expect(']');
        } else if (c == '"') {
            v.kind = JVal::Str;
            v.str = string();
        } else if (c == '-' || std::isdigit((unsigned char)c)) {
            size_t start = pos_;
            if (s_[pos_] == '-') pos_++;
            while (pos_ < s_.size() && (std::isdigit((unsigned char)s_[pos_]) ||
                   s_[pos_] == '.' || s_[pos_] == 'e' || s_[pos_] == 'E' ||
                   s_[pos_] == '+' || s_[pos_] == '-')) pos_++;
            std::string t = s_.substr(start, pos_ - start);
            v.kind = JVal::Num;
            try { v.num = std::stod(t); } catch (...) { fail("'" + t + "' is not a number"); }
            v.integral = t.find_first_of(".eE") == std::string::npos;
        } else if (word("true")) {
            v.kind = JVal::Bool; v.b = true;
        } else if (word("false")) {
            v.kind = JVal::Bool; v.b = false;
        } else if (word("null")) {
            v.kind = JVal::Null;
        } else {
            fail(std::string("unexpected character '") + c + "'");
        }
        return v;
    }

    std::string string() {
        pos_++;   // opening quote
        std::string r;
        while (true) {
            if (pos_ >= s_.size() || s_[pos_] == '\n') fail("a string has no closing quote");
            char c = s_[pos_++];
            if (c == '"') break;
            if (c != '\\') { r += c; continue; }
            if (pos_ >= s_.size()) fail("a string has no closing quote");
            char e = s_[pos_++];
            switch (e) {
                case '"': r += '"'; break;
                case '\\': r += '\\'; break;
                case '/': r += '/'; break;
                case 'n': r += '\n'; break;
                case 'r': r += '\r'; break;
                case 't': r += '\t'; break;
                case 'b': r += '\b'; break;
                case 'f': r += '\f'; break;
                case 'u': {
                    if (pos_ + 4 > s_.size()) fail("a \\u escape needs four hex digits");
                    unsigned cp = 0;
                    for (int i = 0; i < 4; i++) {
                        char h = s_[pos_++];
                        if (!std::isxdigit((unsigned char)h)) fail("a \\u escape needs four hex digits");
                        cp = cp * 16 + (unsigned)(std::isdigit((unsigned char)h) ? h - '0'
                                                  : std::toupper((unsigned char)h) - 'A' + 10);
                    }
                    // UTF-8, as the source text around it is.
                    if (cp < 0x80) r += (char)cp;
                    else if (cp < 0x800) { r += (char)(0xC0 | (cp >> 6)); r += (char)(0x80 | (cp & 0x3F)); }
                    else { r += (char)(0xE0 | (cp >> 12)); r += (char)(0x80 | ((cp >> 6) & 0x3F));
                           r += (char)(0x80 | (cp & 0x3F)); }
                    break;
                }
                default: fail(std::string("'\\") + e + "' is not a JSON escape");
            }
        }
        return r;
    }
};

// ---- From JSON values to the display file ---------------------------------

class Builder {
public:
    explicit Builder(const std::string& file) : file_(file) {}

    DspfFile file(const JVal& root, const std::string& name) {
        need(root, JVal::Obj, "the file");
        known(root, "the file", {"name", "indara", "records"});
        DspfFile f;
        f.name = name;
        if (auto* v = root.get("indara")) f.indara = boolean(*v, "indara");
        const JVal* recs = root.get("records");
        if (!recs) fail(root, "the file has no \"records\" array");
        need(*recs, JVal::Arr, "\"records\"");
        for (const auto& r : recs->arr) f.records.push_back(record(r));
        return f;
    }

private:
    const std::string& file_;

    [[noreturn]] void fail(const JVal& at, const std::string& msg) {
        throw std::runtime_error(file_ + ":" + std::to_string(at.line) + ": " + msg);
    }
    static const char* kindName(JVal::Kind k) {
        switch (k) {
            case JVal::Null: return "null";
            case JVal::Bool: return "true or false";
            case JVal::Num: return "a number";
            case JVal::Str: return "a string";
            case JVal::Arr: return "an array";
            case JVal::Obj: return "an object";
        }
        return "?";
    }
    void need(const JVal& v, JVal::Kind k, const std::string& what) {
        if (v.kind != k)
            fail(v, what + " must be " + kindName(k) + ", not " + kindName(v.kind));
    }
    // A misspelled member would otherwise be silently ignored.
    void known(const JVal& o, const std::string& what, std::initializer_list<const char*> names) {
        for (const auto& kv : o.obj) {
            bool ok = false;
            for (const char* n : names) if (kv.first == n) ok = true;
            if (!ok) {
                std::string list;
                for (const char* n : names) list += std::string(list.empty() ? "" : ", ") + n;
                fail(kv.second, "\"" + kv.first + "\" is not a member of " + what + " (" + list + ")");
            }
        }
    }
    bool boolean(const JVal& v, const std::string& what) { need(v, JVal::Bool, "\"" + what + "\""); return v.b; }
    std::string str(const JVal& v, const std::string& what) { need(v, JVal::Str, "\"" + what + "\""); return v.str; }
    int integer(const JVal& v, const std::string& what) {
        need(v, JVal::Num, "\"" + what + "\"");
        if (!v.integral || v.num < 0 || v.num > 99999)
            fail(v, "\"" + what + "\" must be a whole number from 0 to 99999");
        return (int)v.num;
    }
    std::vector<std::string> strings(const JVal& v, const std::string& what) {
        need(v, JVal::Arr, "\"" + what + "\"");
        std::vector<std::string> r;
        for (const auto& e : v.arr) r.push_back(str(e, what + "\" entry \""));
        return r;
    }
    std::string required(const JVal& o, const char* key, const std::string& what) {
        const JVal* v = o.get(key);
        if (!v) fail(o, what + " has no \"" + key + "\"");
        return str(*v, key);
    }
    int requiredInt(const JVal& o, const char* key, const std::string& what) {
        const JVal* v = o.get(key);
        if (!v) fail(o, what + " has no \"" + key + "\"");
        return integer(*v, key);
    }
    char oneChar(const JVal& v, const std::string& what, const char* allowed) {
        std::string s = str(v, what);
        if (s.size() != 1 || !std::strchr(allowed, std::toupper((unsigned char)s[0])))
        {
            std::string list;
            for (const char* a = allowed; *a; a++)
                list += std::string(a == allowed ? "" : a[1] ? ", " : " or ") + *a;
            fail(v, "\"" + what + "\" must be " + list + ", not \"" + s + "\"");
        }
        return (char)std::toupper((unsigned char)s[0]);
    }

    DspfRecord record(const JVal& r) {
        need(r, JVal::Obj, "a record");
        DspfRecord rec;
        rec.name = required(r, "name", "a record");
        std::string what = "record " + rec.name;
        known(r, what, {"name", "type", "sfl", "sflpag", "sflsiz", "title", "screen", "window",
                        "wdwborder", "keywords", "literals", "fields", "keys"});
        if (auto* v = r.get("type")) {
            std::string t = str(*v, "type");
            if (t == "normal") rec.recType = RecType::NORMAL;
            else if (t == "sfl") rec.recType = RecType::SFL;
            else if (t == "sflctl") rec.recType = RecType::SFLCTL;
            else fail(*v, what + ": \"type\" must be \"normal\", \"sfl\" or \"sflctl\", not \"" + t + "\"");
        }
        if (rec.recType == RecType::SFLCTL) {
            rec.sflCtlFor = required(r, "sfl", what);
            rec.sflPag = requiredInt(r, "sflpag", what);
            rec.sflSiz = requiredInt(r, "sflsiz", what);
        } else {
            for (const char* k : {"sfl", "sflpag", "sflsiz"})
                if (auto* v = r.get(k)) fail(*v, what + ": \"" + k + "\" belongs to a \"sflctl\" record");
        }
        // The descriptor writes a record's name as its title when it has none.
        if (auto* v = r.get("title")) {
            rec.title = str(*v, "title");
            if (rec.title == rec.name) rec.title.clear();
        }
        if (auto* v = r.get("screen")) {
            need(*v, JVal::Obj, "\"screen\"");
            known(*v, "\"screen\"", {"rows", "cols"});
            rec.screenRows = requiredInt(*v, "rows", "\"screen\"");
            rec.screenCols = requiredInt(*v, "cols", "\"screen\"");
        }
        if (auto* v = r.get("window")) {
            need(*v, JVal::Obj, "\"window\"");
            known(*v, "\"window\"", {"row", "col", "height", "width"});
            rec.winRow = requiredInt(*v, "row", "\"window\"");
            rec.winCol = requiredInt(*v, "col", "\"window\"");
            rec.winHeight = requiredInt(*v, "height", "\"window\"");
            rec.winWidth = requiredInt(*v, "width", "\"window\"");
        }
        if (auto* v = r.get("wdwborder")) {
            need(*v, JVal::Obj, "\"wdwborder\"");
            known(*v, "\"wdwborder\"", {"chars", "color", "dspatr"});
            if (auto* c = v->get("chars")) rec.wdwBorderChars = str(*c, "chars");
            if (auto* c = v->get("color")) rec.wdwBorderColor = str(*c, "color");
            if (auto* c = v->get("dspatr")) rec.wdwBorderAttr = str(*c, "dspatr");
        }
        if (auto* v = r.get("keywords")) rec.keywords = strings(*v, "keywords");
        if (auto* v = r.get("literals")) {
            need(*v, JVal::Arr, "\"literals\"");
            for (const auto& l : v->arr) {
                need(l, JVal::Obj, "a literal");
                known(l, "a literal", {"row", "col", "text", "keywords"});
                DspfLiteral lit;
                lit.row = requiredInt(l, "row", "a literal");
                lit.col = requiredInt(l, "col", "a literal");
                lit.text = required(l, "text", "a literal");
                if (auto* k = l.get("keywords")) lit.keywords = strings(*k, "keywords");
                rec.literals.push_back(lit);
            }
        }
        if (auto* v = r.get("fields")) {
            need(*v, JVal::Arr, "\"fields\"");
            for (const auto& fv : v->arr) {
                need(fv, JVal::Obj, "a field");
                DspfField f;
                f.name = required(fv, "name", "a field");
                std::string fw = "field " + f.name;
                known(fv, fw, {"name", "type", "len", "dec", "io", "row", "col", "keywords"});
                if (auto* t = fv.get("type")) f.dtype = oneChar(*t, "type", "ASPBFLTZ");
                f.len = requiredInt(fv, "len", fw);
                if (f.len < 1) fail(fv, fw + ": \"len\" must be at least 1");
                if (auto* d = fv.get("dec")) f.dec = integer(*d, "dec");
                if (auto* io = fv.get("io")) f.io = oneChar(*io, "io", "IOBH");
                if (f.io != 'H') {
                    f.row = requiredInt(fv, "row", fw);
                    f.col = requiredInt(fv, "col", fw);
                } else {
                    if (auto* p = fv.get("row")) f.row = integer(*p, "row");
                    if (auto* p = fv.get("col")) f.col = integer(*p, "col");
                }
                if (auto* k = fv.get("keywords")) f.keywords = strings(*k, "keywords");
                rec.fields.push_back(f);
            }
        }
        if (auto* v = r.get("keys")) {
            need(*v, JVal::Arr, "\"keys\"");
            for (const auto& kv : v->arr) {
                need(kv, JVal::Obj, "a key");
                known(kv, "a key", {"key", "indicator"});
                DspfKey k;
                k.key = required(kv, "key", "a key");
                if (auto* i = kv.get("indicator")) {
                    k.indicator = integer(*i, "indicator");
                    if (k.indicator > 99) fail(*i, "\"indicator\" must be 0 (none) or 1 to 99");
                }
                rec.keys.push_back(k);
            }
        }
        return rec;
    }
};

} // namespace

DspfFile parseJSONSource(const std::string& filename, const std::string& fileName) {
    std::ifstream in(filename, std::ios::binary);
    if (!in.is_open()) throw std::runtime_error("cannot open " + filename);
    std::stringstream ss;
    ss << in.rdbuf();
    std::string src = ss.str();
    JVal root = Parser(src, filename).parseDocument();
    return Builder(filename).file(root, fileName);
}

} // namespace dspf
