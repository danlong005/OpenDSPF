#ifndef DSPF_DDS_READER_H
#define DSPF_DDS_READER_H

#include "ast.h"
#include <string>

namespace dspf {

// Parse an IBM i DDS A-spec display file source into a DspfFile AST.
// Parse an IBM i DDS A-spec display file source into a DspfFile AST.
// Standard fixed-column DDS layout for display files (1-based positions, as
// "OS/400 DDS Reference: Display Files" states them — note there is no 'K'
// entry at position 17 for display files, that is a physical/logical-file
// convention):
//   1-5:      sequence number (ignored)
//   6:        'A' (form type)
//   7:        '*' marks a comment line
//   8-16:     conditioning — position 8 blank/A/O, 9-16 option indicators
//   17:       name type: 'R' = record format, 'H' = help, blank = field,
//             constant or keyword-only line
//   18:       reserved, must be blank
//   19-28:    name — record format name when position 17 is 'R', field name
//             otherwise; the same 10-column range either way, since position
//             17 is only the type indicator and never part of the name
//   29:       reference ('R' = length and type come from the REF/REFFLD file)
//   30-34:    length, right-adjusted
//   35:       data type / keyboard shift (A/S/P/B/F/L/T/Z/...)
//   36-37:    decimal positions
//   38:       usage (I/O/B/H/M/P)
//   39-41:    line (row)
//   42-44:    position (column)
//   45-80:    functions / keywords / constant text
//
// A '+' or '-' in the last non-blank position of the functions area continues
// the entry on the next specification line. A line with no name and no
// position continues the keyword list of the record's last field or constant,
// or of the record itself before the first one.
//
// Returns a populated DspfFile on success.
// Throws std::runtime_error on parse errors.
//
// Returns a populated DspfFile on success.
// Throws std::runtime_error on parse errors.
DspfFile parseDDS(const std::string& filename, const std::string& basename);

} // namespace dspf

#endif // DSPF_DDS_READER_H
