#ifndef DSPF_JSON_READER_H
#define DSPF_JSON_READER_H

#include <string>
#include "ast.h"

namespace dspf {

// Reads a display file defined in JSON: the same shape as the .dspfd
// descriptor dspfc writes, so a .dspfd is itself valid input, and a tool
// that generates screens can write this instead of DDS. Members a DDS
// source would leave at their defaults may be left out (a record's type,
// title, screen and keyword lists; a field's type, dec, io and keywords).
// Throws std::runtime_error naming the line and member on bad input.
DspfFile parseJSONSource(const std::string& filename, const std::string& fileName);

} // namespace dspf

#endif // DSPF_JSON_READER_H
