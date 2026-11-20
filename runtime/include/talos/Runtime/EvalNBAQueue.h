//===- EvalNBAQueue.h - Ordered generated NBA staging ------------*- C++
//-*-===//

#ifndef TALOS_RUNTIME_EVALNBAQUEUE_H
#define TALOS_RUNTIME_EVALNBAQUEUE_H

#include "talos/Runtime/Runtime.h"
#include <cstdint>

namespace talos::runtime {

// Generated code appends and drains these POD records directly. Only capacity
// growth crosses an allocator boundary; no actor or scheduler work happens
// there. Keeping every record preserves repeated writes and intermediate edges.
struct EvalNBARecord {
  uint64_t site;
  uint64_t offset;
  uint64_t value;
  uint64_t unknown;
};
static_assert(sizeof(EvalNBARecord) == 4 * sizeof(uint64_t));

// A packed wide assignment has one site and destination offset, followed
// by all of its value words and then all of its unknown words. The FIFO
// size and capacity remain in EvalNBARecord units. Legacy chunk sites use
// the top bit and ordinary semantic sites fit in the bottom 48 bits.
inline constexpr uint64_t packedWideNBATag = uint64_t{1} << 62;
inline constexpr bool isPackedWideNBASite(uint64_t site) {
  return (site >> 48) == (packedWideNBATag >> 48);
}
inline constexpr uint64_t packedWideNBARecords(uint64_t words) {
  return (words + 2) / 2;
}

struct EvalNBAQueue {
  EvalNBARecord *data = nullptr;
  uint32_t size = 0;
  uint32_t capacity = 0;
  uint32_t error = TALOS_RT_OK;
};

} // namespace talos::runtime

extern "C" talos_rt_status
talos_rt_v1_eval_nba_reserve(talos_rt_context *context,
                             talos::runtime::EvalNBAQueue *queue);
extern "C" talos_rt_status
talos_rt_v1_eval_nba_reserve_records(talos_rt_context *context,
                                     talos::runtime::EvalNBAQueue *queue,
                                     uint32_t records);

#endif
