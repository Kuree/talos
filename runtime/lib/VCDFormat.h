//===- VCDFormat.h - VCD vector value formatting ---------------*- C++ -*-===//
//
// The value characters of a VCD vector record (IEEE 1800-2023 21.7.2.2),
// formatted a canonical-plane word at a time. Exposed for the runtime unit
// tests, which compare them against a bit-at-a-time reference.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_VCDFORMAT_H
#define TALOS_RUNTIME_LIB_VCDFORMAT_H

#include <cstddef>
#include <cstdint>

namespace talos::runtime::vcd {

/// Writes the `width` (at least one) value characters of the canonical bits
/// [sourceBit, sourceBit + width), most significant first, at `out` and
/// returns their end: `0`/`1` for a known bit, `x` for an unknown zero and `z`
/// for an unknown one. `unknown` is null for a two-state value. Both planes
/// hold `planeBytes` bytes. `out` needs eight bytes of room past the
/// characters.
char *formatVectorDigits(const uint8_t *value, const uint8_t *unknown,
                         size_t planeBytes, uint64_t sourceBit, uint64_t width,
                         char *out);

/// Number of low bits to print under the left-extension rules of Table 21-9.
size_t compactVectorWidth(const uint8_t *value, const uint8_t *unknown,
                          size_t planeBytes, uint64_t sourceBit, uint64_t width);

} // namespace talos::runtime::vcd

#endif // TALOS_RUNTIME_LIB_VCDFORMAT_H
