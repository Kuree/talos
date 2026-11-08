//===- VPIValueChangeQueue.h - Coherent change publications ------*- C++
//-*-===//
#ifndef TALOS_RUNTIME_VPI_VALUE_CHANGE_QUEUE_H
#define TALOS_RUNTIME_VPI_VALUE_CHANGE_QUEUE_H

#include "VPIValueChangePool.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <utility>
#include <vector>

namespace talos::runtime {

// One coherent packed-root publication, after both four-state planes have
// committed. Payloads are snapshots: a later write must not change the value
// delivered for an earlier publication. Selectors are filtered by the adapter.
struct VPIPackedChangePublication {
  uint64_t alias = 0;
  uint64_t oldValue = 0, oldUnknown = 0;
  uint64_t newValue = 0, newUnknown = 0;
  uint64_t time = 0;
  uint32_t width = 0;

  bool changes(uint32_t offset, uint32_t selectedWidth) const {
    if (!width || width > 64 || !selectedWidth || offset >= width ||
        selectedWidth > width - offset)
      return false;
    uint64_t mask =
        selectedWidth == 64 ? UINT64_MAX : (uint64_t{1} << selectedWidth) - 1;
    return ((((oldValue ^ newValue) | (oldUnknown ^ newUnknown)) >> offset) &
            mask) != 0;
  }
};

// C6: a VPI-issued change waits until its issuing application routine returns
// to the simulator. Enter ClientScope around the *application routine*, never
// around vpi_put_value. The simulator explicitly drains after that routine
// returns, before executing further design work. Native/VM store adapters may
// drain immediately after a coherent publication, outside an application call.
// This class owns no VPI handles and does not certify any native writer.
template <typename Record> class VPIValueChangeQueue {
  struct Pending {
    VPIPackedChangePublication publication;
    uint64_t revision;
  };
  VPIValueChangePool<Record> registrations;
  std::vector<Pending> pending;
  size_t head = 0;
  size_t queued = 0;
  uint32_t clients = 0;
  bool draining = false;

public:
  class ClientScope {
    VPIValueChangeQueue &queue;

  public:
    explicit ClientScope(VPIValueChangeQueue &queue) : queue(queue) {
      assert(queue.clients != UINT32_MAX);
      ++queue.clients;
    }
    ~ClientScope() { --queue.clients; }
    ClientScope(const ClientScope &) = delete;
    ClientScope &operator=(const ClientScope &) = delete;
  };

  uint64_t add(uint64_t alias, Record record) {
    return registrations.add(alias, std::move(record));
  }
  bool remove(uint64_t id) noexcept { return registrations.remove(id); }
  Record *find(uint64_t id) { return registrations.find(id); }
  bool watches(uint64_t alias) const { return registrations.watches(alias); }
  uint32_t size() const { return registrations.size(); }
  size_t pendingCount() const { return queued; }

  // Invalid geometry and unchanged values publish nothing. No VPI callback is
  // invoked here, including when a publication came from inside vpi_put_value.
  bool publish(VPIPackedChangePublication publication) {
    if (!publication.width || publication.width > 64)
      return false;
    if (!registrations.watches(publication.alias) ||
        !publication.changes(0, publication.width))
      return true;
    uint64_t mask = publication.width == 64
                        ? UINT64_MAX
                        : (uint64_t{1} << publication.width) - 1;
    publication.oldValue &= mask;
    publication.oldUnknown &= mask;
    publication.newValue &= mask;
    publication.newUnknown &= mask;
    if (queued == pending.size()) {
      if (pending.size() > pending.max_size() / 2)
        return false;
      // Grow only at the live high-water mark. A callback that publishes one
      // replacement event on every invocation reuses the same ring slots.
      std::rotate(pending.begin(), pending.begin() + head, pending.end());
      head = 0;
      pending.resize(pending.empty() ? 8 : pending.size() * 2);
    }
    pending[(head + queued) & (pending.size() - 1)] = {
        publication, registrations.revision()};
    ++queued;
    return true;
  }

  // A callback may remove registrations, add registrations, publish more
  // changes or recursively request a drain. Each publication uses its captured
  // registration frontier; callback-induced changes run after the callback
  // returns. The local event copy survives pending-vector growth.
  template <typename Visitor> void drain(Visitor &&visitor) {
    if (clients || draining)
      return;
    struct Guard {
      VPIValueChangeQueue &queue;
      explicit Guard(VPIValueChangeQueue &queue) : queue(queue) {
        queue.draining = true;
      }
      ~Guard() {
        queue.draining = false;
        if (!queue.queued) {
          queue.head = 0;
        }
      }
    } guard(*this);
    while (queued) {
      const Pending event = pending[head];
      head = (head + 1) & (pending.size() - 1);
      --queued;
      registrations.visit(event.publication.alias, event.revision,
                          [&](uint64_t id, Record &record) {
                            ClientScope client(*this);
                            visitor(id, record, event.publication);
                          });
    }
  }
};
} // namespace talos::runtime

#endif
