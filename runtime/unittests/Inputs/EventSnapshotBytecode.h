// Shared native/wasm test image: two real packed-load observer functions.
#ifndef TALOS_TEST_EVENTSNAPSHOTBYTECODE_H
#define TALOS_TEST_EVENTSNAPSHOTBYTECODE_H

#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHash.h"
#include <cstdint>
#include <cstring>
#include <vector>

namespace talos::test {
inline uint64_t snapshotImageChecksum(const std::vector<uint8_t> &bytes) {
  uint64_t hash = talos_stable_image_checksum(bytes.data(), bytes.size(), 32);
  return hash;
}

inline std::vector<uint8_t> snapshotObserverBytecode() {
  constexpr size_t functions = TALOS_RT_DESIGN_BYTECODE_HEADER_SIZE;
  constexpr size_t layouts = functions + 2 * 96;
  // Six layout records {shape, offset}, then one shape per register.
  constexpr size_t shapes = layouts + 6 * 8;
  constexpr size_t code = shapes + 6 * 24;
  constexpr size_t operands = code + 4 * 32;
  constexpr size_t continuations = operands + 8;
  std::vector<uint8_t> bytes(continuations + 2 * 24, 0);
  auto put = [&](size_t offset, uint64_t value, unsigned count = 8) {
    for (unsigned index = 0; index < count; ++index)
      bytes[offset + index] = static_cast<uint8_t>(value >> (8 * index));
  };
  std::memcpy(bytes.data(), "OBBCDS1\0", 8);
  put(8, TALOS_RT_VERSION, 4);
  put(16, TALOS_RT_DESIGN_BYTECODE_HEADER_SIZE, 4);
  put(24, bytes.size());
  put(40, functions);
  put(48, 2);
  put(56, layouts);
  put(64, 6);
  put(200, shapes);
  put(208, 6);
  put(72, code);
  put(80, 4);
  put(88, operands);
  put(96, 1);
  put(104, continuations);
  put(112, 0);
  put(120, continuations);
  put(128, 2);
  for (size_t field : {136, 152, 168, 184})
    put(field, bytes.size());
  for (uint32_t function = 0; function != 2; ++function) {
    size_t f = functions + function * 96;
    put(f, function ? 991 : 979);
    put(f + 16, function * 2);
    put(f + 24, 2);
    put(f + 32, function * 3);
    put(f + 40, 3);
    put(f + 48, 2, 4);
    put(f + 52, 1, 4);
    put(f + 56, function ? 96 : 80);
    put(f + 64, 8);
    put(f + 72, function);
    put(f + 80, 1);
    for (uint32_t index = 0; index != 3; ++index) {
      uint32_t reg = function * 3 + index;
      put(layouts + reg * 8, reg, 4);
      put(layouts + reg * 8 + 4, index * 32, 4);
      size_t shape = shapes + reg * 24;
      bytes[shape] = index == 2 ? TALOS_RT_DBREG_LOGIC : TALOS_RT_DBREG_HANDLE;
      put(shape + 4, index == 2 ? (function ? 65 : 1) : 256, 4);
      put(shape + 8, index == 2 ? (function ? 32 : 16) : 32);
    }
    size_t load = code + function * 64;
    put(load, TALOS_RT_DB_LOAD_STATE, 2);
    put(load + 4, 2, 4);
    put(load + 8, 1, 4);
    size_t ret = load + 32;
    put(ret, TALOS_RT_DB_RETURN, 2);
    put(ret + 12, 1, 4);
    put(continuations + function * 24, function, 4);
    put(continuations + function * 24 + 8, function * 2);
  }
  put(operands, 2, 4);
  put(operands + 4, 2, 4);
  put(32, snapshotImageChecksum(bytes));
  return bytes;
}
} // namespace talos::test
#endif
