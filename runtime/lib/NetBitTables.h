//===- NetBitTables.h - Dense per-net-bit tables of the net alias cache ---===//
//
// The net alias cache keys several tables by state bit or by component root
// (itself a net bit). Per-bit hash maps there dominated context creation and
// teardown of large designs (two-tier B4: BP built 1.5M hash entries and one
// heap vector per component). Net records are sorted and disjoint (the image
// validator rejects anything else), so a net bit maps to a dense index with
// one binary search, and these tables are vectors over that index.
//
// Each table keeps the map interface its callers use (find/end/at, an entry
// with `first` and `second`). Tables share one index and root vector through
// a shared_ptr so the cache stays movable.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_NETBITTABLES_H
#define TALOS_RUNTIME_LIB_NETBITTABLES_H

#include "ExceptionSupport.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <utility>
#include <vector>

[[noreturn]] inline void talosNetTableMissing() {
#if defined(__cpp_exceptions) || defined(_CPPUNWIND)
  throw std::out_of_range("net table key is not a net bit or component root");
#else
  std::abort();
#endif
}

/// Dense indices of the bits of sorted, disjoint net ranges.
class NetBitIndex {
public:
  /// `ranges` holds objects with `valueOffset` and `width`, sorted by offset
  /// and disjoint.
  template <typename Range> void assign(const std::vector<Range> &ranges) {
    offsets.clear();
    bases.clear();
    widths.clear();
    offsets.reserve(ranges.size());
    bases.reserve(ranges.size());
    widths.reserve(ranges.size());
    total = 0;
    for (const Range &range : ranges) {
      offsets.push_back(range.valueOffset);
      bases.push_back(total);
      widths.push_back(range.width);
      total += range.width;
    }
  }

  /// The position in the assigned ranges of the one holding `bit`, or
  /// SIZE_MAX when none does.
  size_t range(uint64_t bit) const {
    auto after = std::upper_bound(offsets.begin(), offsets.end(), bit);
    if (after == offsets.begin())
      return SIZE_MAX;
    size_t net = static_cast<size_t>(after - offsets.begin()) - 1;
    return bit - offsets[net] < widths[net] ? net : SIZE_MAX;
  }

  /// The dense index of `bit`, or UINT64_MAX when no net holds it.
  uint64_t find(uint64_t bit) const {
    size_t net = range(bit);
    return net == SIZE_MAX ? UINT64_MAX : bases[net] + (bit - offsets[net]);
  }

  uint64_t size() const { return total; }

private:
  std::vector<uint64_t> offsets, bases, widths;
  uint64_t total = 0;
};

/// The dense net-bit index plus each bit's connectivity root, built once and
/// shared by every table keyed by bit or by root.
struct NetComponentIndex {
  NetBitIndex bits;
  /// `rootByIndex[i]` is the root bit of dense index i's component; a root is
  /// its component's lowest member bit.
  std::vector<uint64_t> rootByIndex;

  /// The dense index of `root` when it is a component root, else UINT64_MAX.
  uint64_t rootIndex(uint64_t root) const {
    uint64_t at = bits.find(root);
    return at != UINT64_MAX && rootByIndex[at] == root ? at : UINT64_MAX;
  }
};

/// Root of every net bit's connectivity component.
class NetRootByBit {
public:
  struct value_type {
    uint64_t first = 0, second = 0;
  };
  class const_iterator {
  public:
    const_iterator() = default;
    explicit const_iterator(value_type entry) : entry(entry), valid(true) {}
    const value_type &operator*() const { return entry; }
    const value_type *operator->() const { return &entry; }
    bool operator==(const const_iterator &other) const {
      return valid == other.valid &&
             (!valid || entry.first == other.entry.first);
    }
    bool operator!=(const const_iterator &other) const {
      return !(*this == other);
    }

  private:
    value_type entry;
    bool valid = false;
  };

  void assign(std::shared_ptr<const NetComponentIndex> componentIndex) {
    components = std::move(componentIndex);
  }
  const_iterator find(uint64_t bit) const {
    uint64_t at = components ? components->bits.find(bit) : UINT64_MAX;
    return at == UINT64_MAX
               ? end()
               : const_iterator({bit, components->rootByIndex[at]});
  }
  const_iterator end() const { return {}; }
  uint64_t at(uint64_t bit) const {
    const_iterator found = find(bit);
    if (found == end())
      talosNetTableMissing();
    return found->second;
  }

private:
  std::shared_ptr<const NetComponentIndex> components;
};

/// A list of `T` per connectivity component, keyed by its root, stored as one
/// array sliced by root index.
template <typename T> class NetRootLists {
public:
  struct Items {
    const T *first = nullptr, *last = nullptr;
    const T *begin() const { return first; }
    const T *end() const { return last; }
    bool empty() const { return first == last; }
    size_t size() const { return static_cast<size_t>(last - first); }
    const T &front() const { return *first; }
  };
  struct value_type {
    uint64_t first = 0;
    Items second;
  };
  class const_iterator {
  public:
    const_iterator() = default;
    explicit const_iterator(value_type entry) : entry(entry), valid(true) {}
    const value_type &operator*() const { return entry; }
    const value_type *operator->() const { return &entry; }
    bool operator==(const const_iterator &other) const {
      return valid == other.valid &&
             (!valid || entry.first == other.entry.first);
    }
    bool operator!=(const const_iterator &other) const {
      return !(*this == other);
    }

  private:
    value_type entry;
    bool valid = false;
  };

  /// `entries` pairs a component's root index (the dense index of its root
  /// bit) with an item; each root's items keep their order in `entries`.
  void assign(std::shared_ptr<const NetComponentIndex> componentIndex,
              const std::vector<std::pair<uint64_t, T>> &entries) {
    components = std::move(componentIndex);
    uint64_t total = components->bits.size();
    starts.assign(total + 1, 0);
    for (const auto &entry : entries)
      ++starts[entry.first + 1];
    for (uint64_t at = 0; at != total; ++at)
      starts[at + 1] += starts[at];
    items.assign(entries.size(), T{});
    std::vector<uint64_t> next(starts.begin(), starts.end() - 1);
    for (const auto &entry : entries)
      items[next[entry.first]++] = entry.second;
  }
  /// The root's items; a component without items is found and empty.
  const_iterator find(uint64_t root) const {
    uint64_t at = components ? components->rootIndex(root) : UINT64_MAX;
    if (at == UINT64_MAX)
      return end();
    return const_iterator({root, Items{items.data() + starts[at],
                                       items.data() + starts[at + 1]}});
  }
  const_iterator end() const { return {}; }
  Items at(uint64_t root) const {
    const_iterator found = find(root);
    if (found == end())
      talosNetTableMissing();
    return found->second;
  }

private:
  std::shared_ptr<const NetComponentIndex> components;
  std::vector<uint64_t> starts;
  std::vector<T> items;
};

/// The member bits of each connectivity component, keyed by its root, in
/// ascending order.
using NetComponentMembers = NetRootLists<uint64_t>;

/// The effective resolution kind of each connectivity component, keyed by
/// its root.
class NetResolutionByRoot {
public:
  /// `resolutionByIndex` is meaningful at each root's own index.
  void assign(std::shared_ptr<const NetComponentIndex> componentIndex,
              const std::vector<uint64_t> &bitByIndex,
              std::vector<uint8_t> resolutionByIndex) {
    components = std::move(componentIndex);
    resolutions = std::move(resolutionByIndex);
    entries.clear();
    for (size_t at = 0; at != resolutions.size(); ++at)
      if (components->rootByIndex[at] == bitByIndex[at])
        entries.emplace_back(bitByIndex[at], resolutions[at]);
  }
  /// Every component root with its resolution, in ascending root order.
  std::vector<std::pair<uint64_t, uint8_t>>::const_iterator begin() const {
    return entries.begin();
  }
  std::vector<std::pair<uint64_t, uint8_t>>::const_iterator end() const {
    return entries.end();
  }
  uint8_t at(uint64_t root) const {
    uint64_t at = components ? components->rootIndex(root) : UINT64_MAX;
    if (at == UINT64_MAX)
      talosNetTableMissing();
    return resolutions[at];
  }

private:
  std::shared_ptr<const NetComponentIndex> components;
  std::vector<uint8_t> resolutions;
  std::vector<std::pair<uint64_t, uint8_t>> entries;
};

#endif // TALOS_RUNTIME_LIB_NETBITTABLES_H
