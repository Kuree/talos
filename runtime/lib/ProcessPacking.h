//===- ProcessPacking.h - Packed plane access and handle decoding -*- C++
//-*-===//
//
// Bit-plane accessors and stable-handle decoding shared by the process and
// scheduler translation units.  These are leaf helpers on the hot path, so
// they are inline rather than a separate translation unit.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_PROCESSPACKING_H
#define TALOS_RUNTIME_LIB_PROCESSPACKING_H

#include "talos/Runtime/StableHandle.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <vector>

inline bool decodeNativeAutomatic(uint64_t handle, uint32_t &id,
                                  int64_t &offset) {
  talos_rt_stable_handle_v1 decoded;
  if (!talos_rt_stable_handle_decode(handle, &decoded) ||
      decoded.kind != TALOS_RT_STABLE_HANDLE_AUTOMATIC)
    return false;
  id = decoded.id;
  offset = decoded.offset;
  return true;
}

inline bool decodeNativeGlobal(uint64_t handle, int64_t &offset) {
  talos_rt_stable_handle_v1 decoded;
  if (!talos_rt_stable_handle_decode(handle, &decoded) ||
      decoded.kind != TALOS_RT_STABLE_HANDLE_GLOBAL)
    return false;
  offset = decoded.offset;
  return true;
}

inline bool decodeNativeStatic(uint64_t handle, uint32_t &id, int64_t &offset) {
  talos_rt_stable_handle_v1 decoded;
  if (!talos_rt_stable_handle_decode(handle, &decoded) ||
      decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC)
    return false;
  id = decoded.id;
  offset = decoded.offset;
  return true;
}

inline bool addHandleOffset(int64_t base, uint64_t offset, int64_t &result) {
  if (offset > static_cast<uint64_t>(INT64_MAX) ||
      base > INT64_MAX - static_cast<int64_t>(offset))
    return false;
  result = base + static_cast<int64_t>(offset);
  return true;
}

inline uint64_t nativeHandleOffset(uint64_t handle, int64_t amount) {
  return talos_rt_stable_handle_offset(handle, amount);
}

inline uint64_t packedWidthMask(uint64_t bitWidth) {
  return bitWidth == 64 ? UINT64_MAX : (uint64_t{1} << bitWidth) - 1;
}

template <typename T> inline T packedLittleEndian(T word) {
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  if constexpr (sizeof(T) == 2)
    return __builtin_bswap16(word);
  if constexpr (sizeof(T) == 4)
    return __builtin_bswap32(word);
  if constexpr (sizeof(T) == 8)
    return __builtin_bswap64(word);
#endif
  return word;
}

template <typename T> inline T loadPackedWord(const uint8_t *bytes) {
  T word;
  std::memcpy(&word, bytes, sizeof(word));
  return packedLittleEndian(word);
}

template <typename T> inline void storePackedWord(uint8_t *bytes, T word) {
  word = packedLittleEndian(word);
  std::memcpy(bytes, &word, sizeof(word));
}

// Access exactly 2 through 8 bytes. Overlapping the first and last native
// words handles odd sizes without touching the memory beyond the field.
inline uint64_t loadPackedSpan(const uint8_t *bytes, unsigned count) {
  if (count == 8)
    return loadPackedWord<uint64_t>(bytes);
  if (count >= 4)
    return loadPackedWord<uint32_t>(bytes) |
           (uint64_t{loadPackedWord<uint32_t>(bytes + count - 4)}
            << ((count - 4) * 8));
  return loadPackedWord<uint16_t>(bytes) |
         (uint64_t{loadPackedWord<uint16_t>(bytes + count - 2)}
          << ((count - 2) * 8));
}

inline void storePackedSpan(uint8_t *bytes, unsigned count, uint64_t value) {
  if (count == 8) {
    storePackedWord(bytes, value);
  } else if (count >= 4) {
    storePackedWord(bytes, static_cast<uint32_t>(value));
    storePackedWord(bytes + count - 4,
                    static_cast<uint32_t>(value >> ((count - 4) * 8)));
  } else {
    storePackedWord(bytes, static_cast<uint16_t>(value));
    storePackedWord(bytes + count - 2,
                    static_cast<uint16_t>(value >> ((count - 2) * 8)));
  }
}

// Test only the requested bits, without reading beyond their final byte.
// Publication matching needs existence, not a per-bit edge reconstruction.
inline bool anyPackedBits(const uint8_t *plane, uint64_t bitOffset,
                          uint64_t bitWidth) {
  if (!plane || bitWidth == 0)
    return false;
  plane += bitOffset / 8;
  unsigned shift = bitOffset % 8;
  if (shift) {
    uint64_t count = std::min<uint64_t>(bitWidth, 8 - shift);
    if ((*plane >> shift) & packedWidthMask(count))
      return true;
    ++plane;
    bitWidth -= count;
  }
  while (bitWidth >= 64) {
    uint64_t word;
    std::memcpy(&word, plane, sizeof(word));
    if (word)
      return true;
    plane += 8;
    bitWidth -= 64;
  }
  if (bitWidth >= 32) {
    uint32_t word;
    std::memcpy(&word, plane, sizeof(word));
    if (word)
      return true;
    plane += 4;
    bitWidth -= 32;
  }
  if (bitWidth >= 16) {
    uint16_t word;
    std::memcpy(&word, plane, sizeof(word));
    if (word)
      return true;
    plane += 2;
    bitWidth -= 16;
  }
  if (bitWidth >= 8) {
    if (*plane)
      return true;
    ++plane;
    bitWidth -= 8;
  }
  return bitWidth && (*plane & packedWidthMask(bitWidth));
}

template <typename Plane>
inline uint64_t loadPackedBits(const Plane &plane, uint64_t bitOffset,
                               uint64_t bitWidth) {
  uint64_t limb = bitOffset / 64;
  uint32_t shift = bitOffset % 64;
  uint64_t value = plane[limb] >> shift;
  if (shift != 0 && bitWidth > 64 - shift)
    value |= plane[limb + 1] << (64 - shift);
  return value & packedWidthMask(bitWidth);
}

inline uint64_t loadPackedBytes(const uint8_t *plane, uint64_t bitOffset,
                                uint64_t bitWidth) {
  if (!plane || !bitWidth)
    return 0;
  const uint8_t *bytes = plane + bitOffset / 8;
  uint32_t shift = bitOffset % 8;
  uint64_t byteCount = (shift + bitWidth + 7) / 8;
  if (byteCount == 1)
    return (*bytes >> shift) & packedWidthMask(bitWidth);
  if (shift == 0) {
    switch (bitWidth) {
    case 16:
      return loadPackedWord<uint16_t>(bytes);
    case 32:
      return loadPackedWord<uint32_t>(bytes);
    case 64:
      return loadPackedWord<uint64_t>(bytes);
    default:
      break;
    }
  }
  uint64_t bits;
  if (byteCount == 9)
    bits = (loadPackedWord<uint64_t>(bytes) >> shift) |
           (uint64_t{bytes[8]} << (64 - shift));
  else
    bits = loadPackedSpan(bytes, byteCount) >> shift;
  return bits & packedWidthMask(bitWidth);
}

template <typename Plane>
inline void storePackedBits(Plane &plane, uint64_t bitOffset, uint64_t bitWidth,
                            uint64_t value) {
  uint64_t limb = bitOffset / 64;
  uint32_t shift = bitOffset % 64;
  uint64_t mask = packedWidthMask(bitWidth);
  value &= mask;
  uint64_t lowMask = mask << shift;
  plane[limb] = (plane[limb] & ~lowMask) | (value << shift);
  if (shift != 0 && bitWidth > 64 - shift) {
    uint32_t lowBits = 64 - shift;
    uint64_t highMask = mask >> lowBits;
    plane[limb + 1] = (plane[limb + 1] & ~highMask) | (value >> lowBits);
  }
}

inline void storePackedBytes(uint8_t *plane, uint64_t bitOffset,
                             uint64_t bitWidth, uint64_t value) {
  if (!plane || !bitWidth)
    return;
  uint8_t *bytes = plane + bitOffset / 8;
  uint32_t shift = bitOffset % 8;
  uint64_t byteCount = (shift + bitWidth + 7) / 8;
  if (byteCount == 1) {
    uint8_t mask = static_cast<uint8_t>(packedWidthMask(bitWidth) << shift);
    *bytes = static_cast<uint8_t>((*bytes & ~mask) | ((value << shift) & mask));
    return;
  }
  if (shift == 0) {
    switch (bitWidth) {
    case 16:
      storePackedWord(bytes, static_cast<uint16_t>(value));
      return;
    case 32:
      storePackedWord(bytes, static_cast<uint32_t>(value));
      return;
    case 64:
      storePackedWord(bytes, value);
      return;
    default:
      break;
    }
  }
  uint64_t mask = packedWidthMask(bitWidth);
  value &= mask;
  if (byteCount == 9) {
    uint64_t old = loadPackedWord<uint64_t>(bytes);
    storePackedWord(bytes, (old & ~(mask << shift)) | (value << shift));
    unsigned highShift = 64 - shift;
    bytes[8] = static_cast<uint8_t>((bytes[8] & ~(mask >> highShift)) |
                                    (value >> highShift));
  } else {
    uint64_t old = loadPackedSpan(bytes, byteCount);
    storePackedSpan(bytes, byteCount,
                    (old & ~(mask << shift)) | (value << shift));
  }
}

#endif // TALOS_RUNTIME_LIB_PROCESSPACKING_H
