#ifndef DSPF_DDS_READER_H
#define DSPF_DDS_READER_H

#include "ast.h"
#include <string>

namespace dspf {

// Parse an IBM i DDS A-spec display file source into a DspfFile AST.
// Supports the standard fixed-column DDS layout for display files, 1-based
// column numbers verified against "OS/400 DDS Reference: Display Files"
// (there is no 'K' entry at position 17 for display files — that's a
// physical/logical-file DDS convention, not display files):
//   col  6:      'A' (form type)
//   col  7:      '*' whole-line comment
//   cols 7-16:   conditioning (option indicators)
//   col  17:     'R'=record, 'H'=help, blank=field or keyword-only
//   col  18:     reserved
//   cols 19-28:  name (record format name when col 17='R', field name
//                otherwise — the same 10-column range either way; col 17
//                is only the type indicator, never part of the name)
//   col  29:     reference (R)
//   cols 30-34:  field length
//   col  35:     data type / keyboard shift (A/S/P/B/F/L/T/Z/...)
//   cols 36-37:  decimal positions
//   col  38:     usage (I/O/B/H/M/P)
//   cols 39-41:  line (row)
//   cols 42-44:  position (column)
//   cols 45-80:  functions / keywords / literal text
//
// Returns a populated DspfFile on success.
// Throws std::runtime_error on parse errors.
DspfFile parseDDS(const std::string& filename, const std::string& basename);

} // namespace dspf

#endif // DSPF_DDS_READER_H
