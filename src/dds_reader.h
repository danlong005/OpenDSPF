#ifndef DSPF_DDS_READER_H
#define DSPF_DDS_READER_H

#include "ast.h"
#include <string>

namespace dspf {

// Parse an IBM i DDS A-spec display file source into a DspfFile AST.
// Supports the standard fixed-column DDS layout for display files:
//   col  6:      'A' (form type)
//   col  17:     'R'=record, 'K'=key, ' '=field or keyword-only
//   cols 17-26:  field name
//   cols 19-28:  record name (when col 17 = 'R')
//   cols 19+:    key name   (when col 17 = 'K')
//   cols 29-33:  field length
//   col  34:     data type  (A/S/P/B/F/L/T/Z)
//   cols 35-36:  decimal positions
//   col  38:     usage      (I/O/B/H)
//   cols 39-41:  line (row)
//   cols 42-44:  position (column)
//   cols 45-80:  functions / keywords / literal text
//
// Returns a populated DspfFile on success.
// Throws std::runtime_error on parse errors.
DspfFile parseDDS(const std::string& filename, const std::string& basename);

} // namespace dspf

#endif // DSPF_DDS_READER_H
