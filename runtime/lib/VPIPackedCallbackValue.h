//===- VPIPackedCallbackValue.h - Packed callback value payloads -*- C++
//-*-===//
#ifndef TALOS_RUNTIME_VPI_PACKED_CALLBACK_VALUE_H
#define TALOS_RUNTIME_VPI_PACKED_CALLBACK_VALUE_H

#include <array>
#include <cstdint>

#include "sv_vpi_user.h"
#include "talos/vpi_user_compat.h"
#include "vpi_user.h"

namespace talos::runtime {

// Per-invocation storage: VPI calls made by a callback cannot invalidate its
// time/vector/string payload. No shared VPI scratch and no heap allocation.
// The binder resolves vpiObjTypeVal and rejects unsupported strength/real
// sources before this formatter. Inputs use the runtime's (value, unknown)
// X=(0,1), Z=(1,1) planes. Net scalar H/L strength refinement belongs to the
// adapter that owns the publication's strength snapshot.
class VPIPackedCallbackValue {
  std::array<char, 65> string{};
  std::array<s_vpi_vecval, 2> vector{};
  s_vpi_time time{};

public:
  VPIPackedCallbackValue() = default;
  VPIPackedCallbackValue(const VPIPackedCallbackValue &) = delete;
  VPIPackedCallbackValue &operator=(const VPIPackedCallbackValue &) = delete;

  bool format(s_vpi_value &out, uint32_t width, bool isSigned, uint64_t value,
              uint64_t unknown) {
    if (!width || width > 64)
      return false;
    const uint64_t mask = width == 64 ? UINT64_MAX : (uint64_t{1} << width) - 1;
    value &= mask;
    unknown &= mask;
    const uint64_t known = value & ~unknown;
    switch (out.format) {
    case vpiSuppressVal:
      return true;
    case vpiIntVal: {
      uint32_t low = static_cast<uint32_t>(known);
      if (isSigned && width < 32 && (low & (uint32_t{1} << (width - 1))))
        low |= UINT32_MAX << width;
      out.value.integer = static_cast<PLI_INT32>(low);
      return true;
    }
    case vpiScalarVal:
      out.value.scalar = (unknown & 1) ? ((value & 1) ? vpiZ : vpiX)
                                       : ((value & 1) ? vpi1 : vpi0);
      return true;
    case vpiVectorVal: {
      const uint64_t aval = value ^ unknown;
      for (unsigned i = 0; i != (width + 31) / 32; ++i)
        vector[i] = {static_cast<PLI_UINT32>(aval >> (i * 32)),
                     static_cast<PLI_UINT32>(unknown >> (i * 32))};
      out.value.vector = vector.data();
      return true;
    }
    case vpiTimeVal:
      time = {};
      time.type = vpiSimTime;
      time.high = static_cast<PLI_UINT32>(known >> 32);
      time.low = static_cast<PLI_UINT32>(known);
      out.value.time = &time;
      return true;
    case vpiRealVal: {
      const bool negative = isSigned && ((known >> (width - 1)) & 1);
      const uint64_t magnitude = negative ? (-known & mask) : known;
      out.value.real = negative ? -static_cast<double>(magnitude)
                                : static_cast<double>(magnitude);
      return true;
    }
    case vpiStringVal: {
      const unsigned bytes = (width + 7) / 8;
      for (unsigned byte = 0; byte != bytes; ++byte) {
        const char ch = static_cast<char>((known >> (byte * 8)) & 255);
        string[bytes - 1 - byte] = ch ? ch : ' ';
      }
      string[bytes] = 0;
      out.value.str = string.data();
      return true;
    }
    case vpiDecStrVal: {
      unsigned count = 0;
      if (unknown) {
        string[count++] = 'x';
      } else {
        const bool negative = isSigned && ((value >> (width - 1)) & 1);
        uint64_t magnitude = negative ? (-value & mask) : value;
        do {
          string[count++] = static_cast<char>('0' + magnitude % 10);
          magnitude /= 10;
        } while (magnitude);
        if (negative)
          string[count++] = '-';
        for (unsigned i = 0; i != count / 2; ++i) {
          const char ch = string[i];
          string[i] = string[count - 1 - i];
          string[count - 1 - i] = ch;
        }
      }
      string[count] = 0;
      out.value.str = string.data();
      return true;
    }
    case vpiBinStrVal:
    case vpiOctStrVal:
    case vpiHexStrVal: {
      const unsigned digitBits = out.format == vpiBinStrVal   ? 1
                                 : out.format == vpiOctStrVal ? 3
                                                              : 4;
      const unsigned count = (width + digitBits - 1) / digitBits;
      for (unsigned i = 0; i != count; ++i) {
        const unsigned shift = i * digitBits;
        const unsigned bits =
            width - shift < digitBits ? width - shift : digitBits;
        const uint64_t digitMask = (uint64_t{1} << bits) - 1;
        const uint64_t v = (value >> shift) & digitMask;
        const uint64_t u = (unknown >> shift) & digitMask;
        const bool x = (u & ~v) != 0;
        const bool z = (u & v) != 0;
        string[count - 1 - i] = !u                     ? "0123456789abcdef"[v]
                                : u == digitMask && !z ? 'x'
                                : u == digitMask && !x ? 'z'
                                : x                    ? 'X'
                                                       : 'Z';
      }
      string[count] = 0;
      out.value.str = string.data();
      return true;
    }
    default:
      return false;
    }
  }
};
} // namespace talos::runtime

#endif
