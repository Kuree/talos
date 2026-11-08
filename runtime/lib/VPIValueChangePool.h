//===- VPIValueChangePool.h - Stable pooled change registrations -*- C++
//-*-===//
#ifndef TALOS_RUNTIME_VPI_VALUE_CHANGE_POOL_H
#define TALOS_RUNTIME_VPI_VALUE_CHANGE_POOL_H

#include "ExceptionSupport.h"

#include <array>
#include <cassert>
#include <cstdint>
#include <memory>
#include <optional>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace talos::runtime {
// Private registration IDs; the public VPI handle layer owns context identity.
// A publication captures revision(), then visits only registrations that were
// live at that publication. Removal takes effect immediately. Slots removed
// during delivery stay pinned until the outermost visit returns, so callbacks
// may remove themselves/others or register callbacks without invalidating a
// payload reference or an iterator. Callback registration order is preserved.
template <typename Record> class VPIValueChangePool {
  friend struct VPIValueChangePoolTestPeer;
  static_assert(std::is_nothrow_move_constructible_v<Record>);
  static_assert(std::is_nothrow_destructible_v<Record>);
  static constexpr uint32_t None = UINT32_MAX;
  static constexpr uint32_t ChunkSize = 64;
  static constexpr uint32_t EmptyAliasLimit = 256;
  struct Slot {
    std::optional<Record> record;
    uint64_t alias = 0, sequence = 0;
    uint32_t generation = 1;
    uint32_t previous = None, next = None, recycleNext = None;
    bool active = false;
  };
  struct Chain {
    uint32_t head = None, tail = None;
  };
  using Chunk = std::array<Slot, ChunkSize>;
  std::vector<std::unique_ptr<Chunk>> chunks;
  std::unordered_map<uint64_t, Chain> aliases;
  uint64_t nextSequence = 1;
  uint32_t capacity = 0, freeHead = None, deferredHead = None;
  uint32_t activeCount = 0, emptyAliases = 0, depth = 0;

  Slot &slot(uint32_t index) {
    return (*chunks[index / ChunkSize])[index % ChunkSize];
  }
  const Slot &slot(uint32_t index) const {
    return (*chunks[index / ChunkSize])[index % ChunkSize];
  }
  static uint64_t handle(uint32_t index, uint32_t generation) {
    return (uint64_t{generation} << 32) | (uint64_t{index} + 1);
  }
  Slot *lookup(uint64_t id) {
    uint32_t low = static_cast<uint32_t>(id);
    if (!low || low - 1 >= capacity)
      return nullptr;
    auto &s = slot(low - 1);
    return s.active && s.generation == id >> 32 ? &s : nullptr;
  }
  bool ensureFree() {
    if (freeHead != None)
      return true;
    if (uint64_t{capacity} + ChunkSize > None)
      return false;
    auto block = std::make_unique<Chunk>();
    chunks.push_back(std::move(block));
    for (uint32_t i = 0; i != ChunkSize; ++i) {
      uint32_t index = capacity + i;
      slot(index).recycleNext = freeHead;
      freeHead = index;
    }
    capacity += ChunkSize;
    return true;
  }
  void recycle(uint32_t index) noexcept {
    auto &s = slot(index);
    s.record.reset();
    // A stale ID must never become live again, even after generation overflow.
    if (s.generation == UINT32_MAX)
      return;
    ++s.generation;
    s.previous = s.next = None;
    s.recycleNext = freeHead;
    freeHead = index;
  }
  void finishVisit() noexcept {
    assert(depth);
    if (--depth)
      return;
    while (deferredHead != None) {
      uint32_t index = deferredHead;
      deferredHead = slot(index).recycleNext;
      recycle(index);
    }
  }

public:
  VPIValueChangePool() = default;
  VPIValueChangePool(const VPIValueChangePool &) = delete;
  VPIValueChangePool &operator=(const VPIValueChangePool &) = delete;
  uint32_t size() const { return activeCount; }
  uint32_t allocatedSlots() const { return capacity; }
  uint32_t cachedAliases() const { return emptyAliases; }
  uint64_t revision() const { return nextSequence - 1; }
  bool watches(uint64_t alias) const {
    auto found = aliases.find(alias);
    return found != aliases.end() && found->second.head != None;
  }
  Record *find(uint64_t id) {
    auto *s = lookup(id);
    return s ? &*s->record : nullptr;
  }
  // Zero reports exhausted identity space; allocation failures follow the
  // runtime's exception policy. A failed add publishes no registration.
  uint64_t add(uint64_t alias, Record record) {
    if (!nextSequence)
      return 0;
    auto [found, inserted] = aliases.try_emplace(alias);
    TALOS_RT_TRY {
      if (!ensureFree()) {
        if (inserted)
          aliases.erase(found);
        return 0;
      }
    }
    TALOS_RT_CATCH_ALL {
      if (inserted)
        aliases.erase(found);
      TALOS_RT_RETHROW;
    }
    auto &chain = found->second;
    if (!inserted && chain.head == None)
      --emptyAliases;
    uint32_t index = freeHead;
    auto &s = slot(index);
    freeHead = s.recycleNext;
    s.alias = alias;
    s.sequence = nextSequence++;
    s.previous = chain.tail;
    s.next = None;
    s.record.emplace(std::move(record));
    s.active = true;
    if (chain.tail != None)
      slot(chain.tail).next = index;
    else
      chain.head = index;
    chain.tail = index;
    ++activeCount;
    return handle(index, s.generation);
  }
  bool remove(uint64_t id) noexcept {
    auto *s = lookup(id);
    if (!s)
      return false;
    auto found = aliases.find(s->alias);
    assert(found != aliases.end());
    auto &chain = found->second;
    if (s->previous != None)
      slot(s->previous).next = s->next;
    else
      chain.head = s->next;
    if (s->next != None)
      slot(s->next).previous = s->previous;
    else
      chain.tail = s->previous;
    if (chain.head == None) {
      if (emptyAliases == EmptyAliasLimit)
        aliases.erase(found);
      else
        ++emptyAliases;
    }
    s->active = false;
    --activeCount;
    uint32_t index = static_cast<uint32_t>(id) - 1;
    if (!depth)
      recycle(index);
    else {
      s->recycleNext = deferredHead;
      deferredHead = index;
    }
    return true;
  }
  template <typename Visitor>
  void visit(uint64_t alias, uint64_t publicationRevision, Visitor &&visitor) {
    auto found = aliases.find(alias);
    if (found == aliases.end())
      return;
    uint32_t cursor = found->second.head;
    ++depth;
    struct Guard {
      VPIValueChangePool &pool;
      ~Guard() { pool.finishVisit(); }
    } guard{*this};
    while (cursor != None) {
      auto &s = slot(cursor);
      if (s.sequence > publicationRevision)
        break;
      uint32_t next = s.next;
      if (s.active)
        visitor(handle(cursor, s.generation), *s.record);
      cursor = next;
    }
  }
};
} // namespace talos::runtime
#endif
