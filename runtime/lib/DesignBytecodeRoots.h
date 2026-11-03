//===- DesignBytecodeRoots.h - Bytecode managed roots ----------*- C++ -*-===//

#ifndef TALOS_RUNTIME_LIB_DESIGNBYTECODEROOTS_H
#define TALOS_RUNTIME_LIB_DESIGNBYTECODEROOTS_H

#include "DesignBytecodeExecution.h"
#include "RuntimeInternal.h"

namespace talos::designbytecode {

/// Whether a frame of `function` can hold managed values (a managed,
/// reference, argument-reference or string register).
bool frameCanHoldManaged(const Image &image, const Function &function);

class ScopedBytecodeFrameRoots {
public:
  /// `knownManaged` is whether the frame can hold managed values when the
  /// caller already knows (0 or 1), or -1 to work it out here.
  ScopedBytecodeFrameRoots(const Image &image, Frame &frame,
                           talos_rt_context *context, int knownManaged = -1);
  ScopedBytecodeFrameRoots(const ScopedBytecodeFrameRoots &) = delete;
  ScopedBytecodeFrameRoots &
  operator=(const ScopedBytecodeFrameRoots &) = delete;
  ~ScopedBytecodeFrameRoots();

  talos_rt_status getStatus() const { return status; }

private:
  struct Roots {
    const Image *image;
    Frame *frame;
  } roots;
  static void enumerate(void *environment, ManagedRootVisit visit,
                        void *visitorEnvironment);
  ManagedRootProvider provider;
  talos_rt_gc_lane_v1 *lane = nullptr;
  talos_rt_status status = TALOS_RT_OK;
  bool pushed = false;
};

} // namespace talos::designbytecode

#endif // TALOS_RUNTIME_LIB_DESIGNBYTECODEROOTS_H
