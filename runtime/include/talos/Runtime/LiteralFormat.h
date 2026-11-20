//===- LiteralFormat.h - Native literal output-list representation --------===//

#ifndef TALOS_RUNTIME_LITERALFORMAT_H
#define TALOS_RUNTIME_LITERALFORMAT_H

#include <cstdint>

namespace talos::runtime::literal_format {

// A literal run is its byte count (1..127) followed by the literal bytes.
// A substitution is three bytes: kind and flags, integral bit width (zero
// for a string handle), and minimum field width. Its value and optional X/Z
// plane are consecutive 64-bit words in the separate operand array.
enum Kind : uint8_t { Binary, Octal, Decimal, Hex, String };
enum : uint8_t {
  KindMask = 7,
  Signed = 8,
  Unknown = 16,
  Left = 32,
  TrimString = 64,
  Field = 128,
  MaxLiteral = Field - 1,
  DefaultWidth = 255
};

} // namespace talos::runtime::literal_format

#endif // TALOS_RUNTIME_LITERALFORMAT_H
