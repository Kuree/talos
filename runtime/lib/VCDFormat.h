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

/// The number of leading characters of the `width` (at least one) value
/// characters at `digits` that a vector record may drop: the reader
/// left-extends a shorter value with `0` before a `1`, and with `x` or `z`
/// from a leading `x` or `z` (Table 21-9). A leading `1` is never dropped, and
/// a `0` before an `x` or `z` is kept.
size_t droppableLeadingDigits(const char *digits, size_t width);

} // namespace talos::runtime::vcd

#endif // TALOS_RUNTIME_LIB_VCDFORMAT_H
