#ifndef DSPF_CODEGEN_H
#define DSPF_CODEGEN_H

#include "ast.h"
#include <string>

namespace dspf {

// Emit the .dspfd JSON descriptor for the display file.
// The descriptor is loaded at runtime by rpg_dspf_runtime.h.
std::string emitJSON(const DspfFile& f);

// Emit the _dspf.h C++ header consumed by rpgc-generated code.
// Contains one buffer struct per record format with per-field char arrays.
std::string emitHeader(const DspfFile& f);

} // namespace dspf

#endif // DSPF_CODEGEN_H
