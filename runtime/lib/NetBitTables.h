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
// with `first` and `second`). Tables share one index through a shared_ptr so
// the cache stays movable.
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

  /// The dense index of `bit`, or UINT64_MAX when no net holds it.
  uint64_t find(uint64_t bit) const {
    auto after = std::upper_bound(offsets.begin(), offsets.end(), bit);
    if (after == offsets.begin())
      return UINT64_MAX;
    size_t net = static_cast<size_t>(after - offsets.begin()) - 1;
    uint64_t local = bit - offsets[net];
    return local < widths[net] ? bases[net] + local : UINT64_MAX;
  }

  uint64_t size() const { return total; }

private:
  std::vector<uint64_t> offsets, bases, widths;
  uint64_t total = 0;
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

  void assign(std::shared_ptr<const NetBitIndex> netIndex,
              std::vector<uint64_t> rootByIndex) {
    index = std::move(netIndex);
    roots = std::move(rootByIndex);
  }
  const_iterator find(uint64_t bit) const {
    uint64_t at = index ? index->find(bit) : UINT64_MAX;
    return at == UINT64_MAX ? end() : const_iterator({bit, roots[at]});
  }
  const_iterator end() const { return {}; }
  uint64_t at(uint64_t bit) const {
    const_iterator found = find(bit);
    if (found == end())
      talosNetTableMissing();
    return found->second;
  }

private:
  std::shared_ptr<const NetBitIndex> index;
  std::vector<uint64_t> roots;
};

/// The member bits of each connectivity component, keyed by its root, in
/// ascending order.
class NetComponentMembers {
public:
  struct Members {
    const uint64_t *first = nullptr, *last = nullptr;
    const uint64_t *begin() const { return first; }
    const uint64_t *end() const { return last; }
    bool empty() const { return first == last; }
    size_t size() const { return static_cast<size_t>(last - first); }
    uint64_t front() const { return *first; }
  };
  struct value_type {
    uint64_t first = 0;
    Members second;
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

  /// `rootByIndex[i]` is the root bit of dense index i's component and
  /// `bitByIndex[i]` its bit; a root is its own component's member.
  void assign(std::shared_ptr<const NetBitIndex> netIndex,
              const std::vector<uint64_t> &rootByIndex,
              const std::vector<uint64_t> &bitByIndex) {
    index = std::move(netIndex);
    uint64_t total = rootByIndex.size();
    roots = rootByIndex;
    starts.assign(total + 1, 0);
    // Count members per root index, then place bits in ascending index (and
    // so ascending bit) order.
    std::vector<uint64_t> rootIndex(total);
    for (uint64_t member = 0; member != total; ++member) {
      rootIndex[member] = index->find(rootByIndex[member]);
      ++starts[rootIndex[member] + 1];
    }
    for (uint64_t at = 0; at != total; ++at)
      starts[at + 1] += starts[at];
    bits.assign(total, 0);
    std::vector<uint64_t> next(starts.begin(), starts.end() - 1);
    for (uint64_t member = 0; member != total; ++member)
      bits[next[rootIndex[member]]++] = bitByIndex[member];
  }
  const_iterator find(uint64_t root) const {
    uint64_t at = index ? index->find(root) : UINT64_MAX;
    if (at == UINT64_MAX || roots[at] != root)
      return end();
    return const_iterator({root, Members{bits.data() + starts[at],
                                         bits.data() + starts[at + 1]}});
  }
  const_iterator end() const { return {}; }
  Members at(uint64_t root) const {
    const_iterator found = find(root);
    if (found == end())
      talosNetTableMissing();
    return found->second;
  }

private:
  std::shared_ptr<const NetBitIndex> index;
  std::vector<uint64_t> roots, starts, bits;
};

/// The effective resolution kind of each connectivity component, keyed by
/// its root.
class NetResolutionByRoot {
public:
  /// `resolutionByIndex` is meaningful at each root's own index, where
  /// `rootByIndex[i] == bitByIndex[i]`.
  void assign(std::shared_ptr<const NetBitIndex> netIndex,
              std::vector<uint64_t> rootByIndex,
              const std::vector<uint64_t> &bitByIndex,
              std::vector<uint8_t> resolutionByIndex) {
    index = std::move(netIndex);
    roots = std::move(rootByIndex);
    resolutions = std::move(resolutionByIndex);
    entries.clear();
    for (size_t at = 0; at != roots.size(); ++at)
      if (roots[at] == bitByIndex[at])
        entries.emplace_back(roots[at], resolutions[at]);
  }
  /// Every component root with its resolution, in ascending root order.
  std::vector<std::pair<uint64_t, uint8_t>>::const_iterator begin() const {
    return entries.begin();
  }
  std::vector<std::pair<uint64_t, uint8_t>>::const_iterator end() const {
    return entries.end();
  }
  uint8_t at(uint64_t root) const {
    uint64_t at = index ? index->find(root) : UINT64_MAX;
    if (at == UINT64_MAX || roots[at] != root)
      talosNetTableMissing();
    return resolutions[at];
  }

private:
  std::shared_ptr<const NetBitIndex> index;
  std::vector<uint64_t> roots;
  std::vector<uint8_t> resolutions;
  std::vector<std::pair<uint64_t, uint8_t>> entries;
};

#endif // TALOS_RUNTIME_LIB_NETBITTABLES_H
