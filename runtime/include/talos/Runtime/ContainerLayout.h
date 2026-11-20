//===- ContainerLayout.h - Native sequential container storage ------------===//

#ifndef TALOS_RUNTIME_CONTAINERLAYOUT_H
#define TALOS_RUNTIME_CONTAINERLAYOUT_H

#include "talos/Runtime/Runtime.h"

namespace talos::runtime_detail {

struct BufferHeader {
  const void *descriptor;
  uint64_t reserved;
};

struct AssociativeKeyLayout {
  const talos_rt_element_type_v1 *element;
  const uint64_t *plan;
};
struct ContainerHeader {
  const void *descriptor;
  talos_rt_container_kind_v1 kind;
  // Mailboxes share queue storage but preserve a distinct object identity.
  uint32_t isMailbox;
  const talos_rt_element_type_v1 *element;
  talos_rt_object_v1 *buffer;
  talos_rt_object_v1 *ordered;
  talos_rt_object_v1 *defaultValue;
  uint64_t size;
  uint64_t capacity;
  uint64_t head;
  uint64_t bound;
  uint64_t epoch;
  talos_rt_assoc_key_kind_v1 keyKind;
  uint32_t hasDefault;
  uint64_t keyWidth;
  talos_rt_object_v1 *referenceBuffer;
  uint64_t referenceCount;
  uint64_t referenceCapacity;
  // Open-addressed index into referenceBuffer. The registry owns weak handles;
  // the index stores only hashes and ordinals, so it needs no element tracer.
  talos_rt_object_v1 *referenceIndex;
  uint64_t referenceIndexCapacity;
  // Associative key descriptors and short scalar queue data occupy
  // mutually exclusive storage.
  union {
    AssociativeKeyLayout associativeKey;
    uint8_t inlineElements[sizeof(AssociativeKeyLayout)];
  };
  // Exact immutable source descriptor for a boxed value. Zero means the box
  // predates VPI metadata; it never means a type inferred from element storage.
  uint64_t boxTypeID;
};

static_assert(sizeof(BufferHeader) == 16);
static_assert(sizeof(ContainerHeader) == (sizeof(void *) == 8 ? 168 : 144));

inline constexpr uint64_t inlineQueueCapacity = 4;

} // namespace talos::runtime_detail

#endif // TALOS_RUNTIME_CONTAINERLAYOUT_H
