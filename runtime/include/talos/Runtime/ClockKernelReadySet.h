//===- ClockKernelReadySet.h - Generated/native ingress contract -*- C++
//-*-===//

#ifndef TALOS_RUNTIME_CLOCKKERNELREADYSET_H
#define TALOS_RUNTIME_CLOCKKERNELREADYSET_H

#include "talos/Runtime/ReadySet.h"
#include "talos/Runtime/Runtime.h"

namespace talos::runtime {

// Opt-in use of the clock kernel's reserved field. ABI layout and leaf count
// stay unchanged. Indexed kernels append ReadySetLayout's cache/summaries;
// dirty kernels append DirtyReadySetLayout's dirty levels; legacy callers
// with reserved == 0 continue to supply only raw leaf words.
inline constexpr uint32_t indexedClockKernelReadySet = 1;
inline constexpr uint32_t dirtyClockKernelReadySet = 2;

inline ReadySetLayout clockKernelReadySetLayout(uint32_t words) {
  return ReadySetLayout(static_cast<uint32_t>(
      std::min(uint64_t{words} * 64, uint64_t{UINT32_MAX})));
}

inline DirtyReadySetLayout clockKernelDirtyReadySetLayout(uint32_t words) {
  return DirtyReadySetLayout(static_cast<uint32_t>(
      std::min(uint64_t{words} * 64, uint64_t{UINT32_MAX})));
}

inline void publishClockKernelReady(const talos_rt_native_clock_kernel &kernel,
                                    uint32_t bit) {
  if (kernel.reserved & dirtyClockKernelReadySet) {
    const uint32_t words = kernel.ingress_word_count;
    if (words <= 64 * DirtyReadySetLayout::flatWordLimit) {
      // The dirty index has at most one summary level. Its first word
      // follows all the leaves. No layout construction is needed per wake.
      uint32_t leaf = bit / 64;
      if (leaf < words) {
        kernel.ingress_mask[leaf] |= uint64_t{1} << (bit % 64);
        if (words > 1)
          kernel.ingress_mask[words + leaf / 64] |= uint64_t{1} << (leaf % 64);
      }
      return;
    }
    const DirtyReadySetLayout layout =
        clockKernelDirtyReadySetLayout(kernel.ingress_word_count);
    DirtyReadySetView(kernel.ingress_mask, layout).set(bit);
  } else if (kernel.reserved & indexedClockKernelReadySet) {
    const ReadySetLayout layout =
        clockKernelReadySetLayout(kernel.ingress_word_count);
    ReadySetView(kernel.ingress_mask, layout).set(bit);
  } else {
    kernel.ingress_mask[bit / 64] |= uint64_t{1} << (bit % 64);
  }
}

// A nonempty set of destinations in a single ingress word. Update the same
// summaries as individual publications, including the cached minimum.
inline void publishClockKernelReadyWord(
    const talos_rt_native_clock_kernel &kernel, uint32_t word, uint64_t mask) {
  if (kernel.reserved & dirtyClockKernelReadySet) {
    uint32_t words = kernel.ingress_word_count;
    if (words <= 64 * DirtyReadySetLayout::flatWordLimit) {
      kernel.ingress_mask[word] |= mask;
      if (words > 1)
        kernel.ingress_mask[words + word / 64] |= uint64_t{1} << (word % 64);
      return;
    }
    const auto layout = clockKernelDirtyReadySetLayout(words);
    DirtyReadySetView(kernel.ingress_mask, layout).setWord(word, mask);
  } else if (kernel.reserved & indexedClockKernelReadySet) {
    const auto layout = clockKernelReadySetLayout(kernel.ingress_word_count);
    ReadySetView(kernel.ingress_mask, layout).setWord(word, mask);
  } else {
    kernel.ingress_mask[word] |= mask;
  }
}

} // namespace talos::runtime
#endif
