//===- FlatU64Table.h - Open-addressing maps and sets of 64-bit keys ------===//
//
// The scheduler indexes processes and design tasks by token or id in hash
// tables it probes and updates on every activation. std::unordered_map and
// std::unordered_set allocate a node per element, so each schedule and
// retirement paid an allocation and a free (two-tier B2 Q8). Tokens and ids
// are never reused, so a vector indexed by token would grow with every process
// ever created; these tables instead keep the elements in one array with
// linear probing, tombstones for erased slots and a mixed hash.
//
// The interface is the subset the runtime uses: find/end/count, emplace and
// operator[] (maps), insert (sets), erase by key, size/empty/clear/reserve and
// iteration in unspecified order. Map erasure leaves the other elements in
// place; inserting a new key may rehash and invalidates all iterators (an
// existing key never rehashes). Sets keep their keys dense and must not be
// modified while iterated (see FlatU64Set). Inserts give the strong exception
// guarantee, as the standard containers do.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_FLATU64TABLE_H
#define TALOS_RUNTIME_LIB_FLATU64TABLE_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <type_traits>
#include <utility>
#include <vector>

namespace talos::runtime {

namespace flat_detail {
enum : uint8_t { kEmpty = 0, kFull = 1, kErased = 2 };

inline uint64_t mix(uint64_t key) {
  key ^= key >> 33;
  key *= UINT64_C(0xff51afd7ed558ccd);
  key ^= key >> 33;
  return key;
}

/// Storage and probing shared by the map and the set. `Slot` holds the key
/// as its `first` member (the set's slot has no value).
template <typename Slot> class Table {
public:
  size_t size() const { return count; }
  bool empty() const { return count == 0; }

  void clear() {
    if (count == 0 && erased == 0)
      return;
    std::fill(control.begin(), control.end(), kEmpty);
    count = 0;
    erased = 0;
  }

  void reserve(size_t elements) {
    if (elements * 4 > capacity() * 3)
      rehash(elements);
  }

protected:
  size_t capacity() const { return control.size(); }

  /// The slot holding `key`, or SIZE_MAX.
  size_t locate(uint64_t key) const {
    if (count == 0)
      return SIZE_MAX;
    size_t mask = capacity() - 1;
    for (size_t at = mix(key) & mask;; at = (at + 1) & mask) {
      if (control[at] == kEmpty)
        return SIZE_MAX;
      if (control[at] == kFull && slots[at].first == key)
        return at;
    }
  }

  /// The slot holding `key`, or a free slot claimed for it (`inserted`).
  /// One probe finds the key or where it goes; only a new key that would
  /// exceed the load bound rehashes, and a rehash that fails to allocate
  /// changes nothing.
  size_t claim(uint64_t key, bool &inserted) {
    inserted = false;
    size_t free = SIZE_MAX;
    if (capacity() != 0) {
      size_t mask = capacity() - 1;
      for (size_t at = mix(key) & mask;; at = (at + 1) & mask) {
        if (control[at] == kFull) {
          if (slots[at].first == key)
            return at;
          continue;
        }
        if (control[at] == kErased) {
          if (free == SIZE_MAX)
            free = at;
          continue;
        }
        if (free == SIZE_MAX)
          free = at;
        break;
      }
    }
    if (free == SIZE_MAX || (control[free] == kEmpty &&
                             (count + erased + 1) * 4 > capacity() * 3)) {
      rehash(count + 1);
      size_t mask = capacity() - 1;
      free = mix(key) & mask;
      while (control[free] != kEmpty)
        free = (free + 1) & mask;
    }
    if (control[free] == kErased)
      --erased;
    control[free] = kFull;
    slots[free] = Slot{};
    slots[free].first = key;
    ++count;
    inserted = true;
    return free;
  }

  size_t eraseKey(uint64_t key) {
    size_t at = locate(key);
    if (at == SIZE_MAX)
      return 0;
    eraseSlot(at);
    return 1;
  }

  void eraseSlot(size_t at) {
    control[at] = kErased;
    --count;
    ++erased;
  }

  size_t nextFull(size_t at) const {
    while (at < capacity() && control[at] != kFull)
      ++at;
    return at;
  }

  std::vector<uint8_t> control;
  std::vector<Slot> slots;

private:
  /// Rebuilds for `elements` live keys at a load of at most one half.
  void rehash(size_t elements) {
    size_t wanted = 16;
    while (wanted < elements * 2)
      wanted *= 2;
    std::vector<uint8_t> oldControl(wanted, kEmpty);
    std::vector<Slot> oldSlots(wanted);
    oldControl.swap(control);
    oldSlots.swap(slots);
    count = 0;
    erased = 0;
    size_t mask = wanted - 1;
    for (size_t at = 0; at != oldControl.size(); ++at) {
      if (oldControl[at] != kFull)
        continue;
      size_t to = mix(oldSlots[at].first) & mask;
      while (control[to] != kEmpty)
        to = (to + 1) & mask;
      control[to] = kFull;
      slots[to] = std::move(oldSlots[at]);
      ++count;
    }
  }

  size_t count = 0;
  size_t erased = 0;
};
} // namespace flat_detail

/// A map from 64-bit keys to `Value`.
template <typename Value> class FlatU64Map {
public:
  struct value_type {
    uint64_t first = 0;
    Value second{};
  };

private:
  class Storage : public flat_detail::Table<value_type> {
    friend class FlatU64Map;
  };

public:
  template <bool Const> class Iterator {
  public:
    using Map = std::conditional_t<Const, const Storage, Storage>;
    using Entry = std::conditional_t<Const, const value_type, value_type>;
    Iterator() = default;
    Iterator(Map *table, size_t at) : table(table), at(at) {}
    Entry &operator*() const { return table->slots[at]; }
    Entry *operator->() const { return &table->slots[at]; }
    Iterator &operator++() {
      at = table->nextFull(at + 1);
      return *this;
    }
    bool operator==(const Iterator &other) const { return at == other.at; }
    bool operator!=(const Iterator &other) const { return at != other.at; }

  private:
    friend class FlatU64Map;
    Map *table = nullptr;
    size_t at = 0;
  };
  using iterator = Iterator<false>;
  using const_iterator = Iterator<true>;

  iterator begin() { return {&storage, storage.nextFull(0)}; }
  iterator end() { return {&storage, storage.capacity()}; }
  const_iterator begin() const { return {&storage, storage.nextFull(0)}; }
  const_iterator end() const { return {&storage, storage.capacity()}; }

  iterator find(uint64_t key) {
    size_t at = storage.locate(key);
    return at == SIZE_MAX ? end() : iterator{&storage, at};
  }
  const_iterator find(uint64_t key) const {
    size_t at = storage.locate(key);
    return at == SIZE_MAX ? end() : const_iterator{&storage, at};
  }
  size_t count(uint64_t key) const { return storage.locate(key) != SIZE_MAX; }

  /// Inserts `key` with `value` unless present (then keeps the old value).
  std::pair<iterator, bool> emplace(uint64_t key, Value value) {
    bool inserted = false;
    size_t at = storage.claim(key, inserted);
    if (inserted)
      storage.slots[at].second = std::move(value);
    return {iterator{&storage, at}, inserted};
  }
  Value &operator[](uint64_t key) {
    bool inserted = false;
    return storage.slots[storage.claim(key, inserted)].second;
  }
  size_t erase(uint64_t key) { return storage.eraseKey(key); }
  /// Erases the element `at` points to (a valid, dereferenceable iterator).
  void erase(iterator at) { storage.eraseSlot(at.at); }

  size_t size() const { return storage.size(); }
  bool empty() const { return storage.empty(); }
  void clear() { storage.clear(); }
  void reserve(size_t elements) { storage.reserve(elements); }

private:
  Storage storage;
};

/// A set of 64-bit keys, kept dense for iteration: the keys sit in a vector
/// (iteration costs the size, not the table capacity, which stays at its
/// high-water mark after a burst of candidates) and a map gives each key's
/// position. Erasing moves the last key into the erased position, so a set
/// must not be modified while it is iterated.
class FlatU64Set {
public:
  using const_iterator = std::vector<uint64_t>::const_iterator;
  using iterator = const_iterator;

  const_iterator begin() const { return items.begin(); }
  const_iterator end() const { return items.end(); }
  size_t count(uint64_t key) const { return positions.count(key); }
  /// Inserts `key` unless present. A failed allocation changes nothing (the
  /// runtime rolls back with erase after a caught bad_alloc).
  std::pair<const_iterator, bool> insert(uint64_t key) {
    // Room first: a present key at most grows the reservation.
    if (items.size() == items.capacity())
      items.reserve(std::max<size_t>(8, items.capacity() * 2));
    auto [found, inserted] = positions.emplace(key, items.size());
    if (inserted)
      items.push_back(key);
    return {items.begin() + found->second, inserted};
  }
  size_t erase(uint64_t key) {
    auto found = positions.find(key);
    if (found == positions.end())
      return 0;
    size_t at = found->second;
    positions.erase(found);
    if (at + 1 != items.size()) {
      items[at] = items.back();
      positions.find(items[at])->second = at;
    }
    items.pop_back();
    return 1;
  }

  size_t size() const { return items.size(); }
  bool empty() const { return items.empty(); }
  void clear() {
    items.clear();
    positions.clear();
  }
  void reserve(size_t elements) {
    items.reserve(elements);
    positions.reserve(elements);
  }

private:
  std::vector<uint64_t> items;
  FlatU64Map<size_t> positions;
};

} // namespace talos::runtime

#endif // TALOS_RUNTIME_LIB_FLATU64TABLE_H
