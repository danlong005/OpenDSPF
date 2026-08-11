#ifndef DSPF_AST_H
#define DSPF_AST_H

#include <string>
#include <vector>

namespace dspf {

// Record format type
enum class RecType { NORMAL, SFL, SFLCTL };

struct DspfField {
    std::string name;
    char  dtype = 'A';  // A=char, S=zoned, P=packed, B=binary, F=float,
                        // L=date, T=time, Z=timestamp (stored as char[], no
                        // date-specific parsing/formatting — see codegen's
                        // cppFieldType default case)
    int   len   = 1;
    int   dec   = 0;
    char  io    = 'O';  // I=input, O=output, B=both, H=hidden
    int   row   = 0;
    int   col   = 0;
    std::vector<std::string> keywords; // e.g. "COLOR(RED)", "DSPATR(HI)", "COND(*IN03)"
};

struct DspfLiteral {
    int row = 0;
    int col = 0;
    std::string text;
    std::vector<std::string> keywords; // e.g. "COND(*IN01)"
};

struct DspfKey {
    std::string key;   // "F3", "F12", "ENTER", "PAGEUP", "PAGEDOWN"
    int indicator = 0; // *INxx number (0 = no indicator assigned)
};

struct DspfRecord {
    std::string name;
    RecType     recType    = RecType::NORMAL;
    std::string sflCtlFor; // SFLCTL: name of associated SFL record
    int         sflPag    = 0;
    int         sflSiz    = 0;
    int screenRows = 24;
    int screenCols = 80;
    std::string title;
    int winRow = 0, winCol = 0, winHeight = 0, winWidth = 0; // 0 = not a window record
    std::string wdwBorderChars; // 8-char border string (IBM i order); empty = ACS defaults
    std::string wdwBorderColor; // "GREEN", "RED", etc.; empty = default
    std::string wdwBorderAttr;  // "HI", "BL", "RI", "UL"; empty = normal
    std::vector<std::string> keywords; // e.g. "OVERLAY", "NOCLEAR", "ALARM", "NOINPUT", "PROTECT(*IN99)"
    std::vector<DspfLiteral> literals;
    std::vector<DspfField>   fields;
    std::vector<DspfKey>     keys;
};

struct DspfFile {
    std::string name;                  // file name (no extension)
    std::vector<DspfRecord> records;
};

} // namespace dspf

#endif // DSPF_AST_H
