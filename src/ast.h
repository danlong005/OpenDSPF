#ifndef DSPF_AST_H
#define DSPF_AST_H

#include <string>
#include <vector>

namespace dspf {

struct DspfField {
    std::string name;
    char  dtype = 'A';  // A=char, S=zoned, P=packed, B=binary, F=float
    int   len   = 1;
    int   dec   = 0;
    char  io    = 'O';  // I=input, O=output, B=both, H=hidden
    int   row   = 0;
    int   col   = 0;
    std::vector<std::string> keywords; // e.g. "COLOR(RED)", "DSPATR(HI)"
};

struct DspfLiteral {
    int row = 0;
    int col = 0;
    std::string text;
};

struct DspfKey {
    std::string key;   // "F3", "F12", "ENTER", "PAGEUP", "PAGEDOWN"
    int indicator = 0; // *INxx number (0 = no indicator assigned)
};

struct DspfRecord {
    std::string name;
    int screenRows = 24;
    int screenCols = 80;
    std::string title;
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
