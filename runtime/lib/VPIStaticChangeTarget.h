//===- VPIStaticChangeTarget.h - Checked packed change slots -----*- C++
//-*-===//
#ifndef TALOS_RUNTIME_VPI_STATIC_CHANGE_TARGET_H
#define TALOS_RUNTIME_VPI_STATIC_CHANGE_TARGET_H

#include "talos/Runtime/Runtime.h"

// Borrowed immutable design metadata; no handle/frame/object is retained.
// The callback adapter must own its object view and certify every native
// writer before publishing a registration. Equal physical ranges can share
// a watch group even when their logical object cursors differ.
struct VPIStaticChangeTarget {
  talos_rt_design_cursor_v1 object{};
  uint64_t rootStateOffset = 0;
  uint64_t rootWidth = 0;
  uint64_t selectedOffset = 0;
  uint64_t selectedWidth = 0;
  uint32_t objectType = 0;
  int32_t valueFormat = 0;
  bool fourState = false;
  bool isSigned = false;
};

// Private fast binding query on the VPI owner thread. It does not register
// callbacks, select an executor or read a value. TIER_UNAVAILABLE means the
// target needs a broader binder (wide roots, real/managed values, expressions,
// terminals or strengths). Automatic variables are forbidden by LRM 37.43.
// Failure clears the output. The first implementation accepts static packed
// integral storage/net roots up to 64 bits and their checked selectors.
extern "C" talos_rt_status
talos_rt_vpi_bind_static_change_target(talos_rt_context *context, void *object,
                                       int32_t format,
                                       VPIStaticChangeTarget *out);

#endif
