//===- ContainerStorageInternal.h - Shared storage ABI -------*- C++ -*-===//

#ifndef TALOS_RUNTIME_LIB_CONTAINERSTORAGEINTERNAL_H
#define TALOS_RUNTIME_LIB_CONTAINERSTORAGEINTERNAL_H

#include "talos/Runtime/ContainerLayout.h"

namespace talos::runtime_detail {

// Physical associative-slot prefix shared with the cold bit-stream exporter.
// Keeping it beside the container header prevents the ordinary and feature
// runtimes from silently disagreeing about the value-plane offset.
struct AssocSlot {
  uint64_t hash;
  uint64_t distance;
  uint64_t integral;
  union {
    talos_rt_string_v1 string;
    talos_rt_object_v1 *object;
  };
};

static_assert(sizeof(AssocSlot) == 32);

inline uint64_t elementStride(const talos_rt_element_type_v1 *element) {
  return element->value_size *
         ((element->flags & TALOS_RT_ELEMENT_FOUR_STATE) ? 2 : 1);
}

// Four small scalar elements and their optional X/Z planes fit in the space
// used by associative key metadata. Traced elements keep a managed buffer.
inline bool supportsInlineQueue(const ContainerHeader &header) {
  const auto *element = header.element;
  return header.kind == TALOS_RT_CONTAINER_QUEUE && !header.isMailbox &&
         element && !element->trace &&
         (element->kind == TALOS_RT_ELEMENT_BITS ||
          element->kind == TALOS_RT_ELEMENT_LOGIC) &&
         element->value_size &&
         element->value_size <=
             sizeof(header.inlineElements) / inlineQueueCapacity /
                 ((element->flags & TALOS_RT_ELEMENT_FOUR_STATE) ? 2 : 1);
}

inline bool hasInlineQueueStorage(const ContainerHeader &header) {
  return !header.buffer && header.capacity == inlineQueueCapacity &&
         supportsInlineQueue(header);
}

inline uint64_t assocValueOffset(const talos_rt_element_type_v1 *element) {
  return (sizeof(AssocSlot) + element->alignment - 1) &
         ~(element->alignment - 1);
}

inline uint64_t assocSlotStride(const talos_rt_element_type_v1 *element) {
  uint64_t alignment = alignof(AssocSlot) > element->alignment
                           ? alignof(AssocSlot)
                           : element->alignment;
  uint64_t size = assocValueOffset(element) + elementStride(element);
  return (size + alignment - 1) & ~(alignment - 1);
}

/// Materialize and publish the cached index-sorted slot order for an
/// associative array. The first ordering pass may allocate the cache.
talos_rt_status ensureAssocOrdered(talos_rt_gc_lane_v1 *lane,
                                   talos_rt_object_v1 *array);
talos_rt_status ensureAssocOrderedWithoutSafepoint(talos_rt_gc_lane_v1 *lane,
                                                   talos_rt_object_v1 *array);

} // namespace talos::runtime_detail

#endif // TALOS_RUNTIME_LIB_CONTAINERSTORAGEINTERNAL_H
