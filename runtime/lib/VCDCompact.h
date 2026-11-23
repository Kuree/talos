//===- VCDCompact.h - Shared prefixes of sampled VCD histories ------------===//
//
// Each node represents a common history up to the next divergence. A sample
// records one value per changed node. Splitting creates children, so a later
// force never needs to re-sample or duplicate earlier values in the journal.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_RUNTIME_LIB_VCDCOMPACT_H
#define TALOS_RUNTIME_LIB_VCDCOMPACT_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <map>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace talos::runtime::vcd {
struct CompactTrace {
  static constexpr uint32_t none = UINT32_MAX;
  struct Group {
    uint32_t size = 0, first = none, changed = 0, node = none;
    bool same = true;
    uint64_t changes = 0, value = 0, unknown = 0;
  };
  struct Field {
    uint32_t group, next, code;
  };
  struct Node {
    uint32_t parent, variable;
  };
  struct HeaderCode {
    size_t offset;
    uint32_t code;
    size_t length;
  };
  struct Span {
    uint32_t begin, end;
  };
  struct Code {
    uint64_t text;
    size_t length;
  };
  struct Layout {
    std::vector<Span> spans;
    std::vector<Code> codes;
    std::vector<uint32_t> physical;
  };
  std::string header;
  std::vector<HeaderCode> headerCodes;
  bool collectingHeader = true;
  std::vector<Group> groups;
  std::vector<Field> fields;
  std::vector<Node> nodes;
  std::vector<uint32_t> touched, changed;
  Layout published;
  std::unique_ptr<std::FILE, decltype(&std::fclose)> journal{nullptr,
                                                             &std::fclose};
  uint64_t bytes = 0, checkpointBytes = 0, samples = 0, lastSplit = 0;
  uint64_t publishedSamples = 0;

  template <typename Variables> void initialize(const Variables &vars) {
    fields.resize(vars.size());
    groups.reserve(vars.size());
    std::map<std::pair<uint64_t, bool>, uint32_t> shapes;
    for (uint32_t i = 0; i < vars.size(); ++i) {
      const auto &v = vars[i];
      auto [it, inserted] =
          shapes.try_emplace({v.width, v.isReal}, groups.size());
      if (inserted) {
        groups.emplace_back();
        groups.back().node = nodes.size();
        nodes.push_back({none, i});
      }
      fields[i] = {it->second, none, v.code};
      ++groups[it->second].size;
    }
  }

  template <typename SameValue>
  void change(uint32_t code, uint64_t value, uint64_t unknown,
              SameValue sameValue) {
    Field &field = fields[code];
    Group &g = groups[field.group];
    if (g.size == 1) {
      g.value = value;
      g.unknown = unknown;
      ++g.changes;
      changed.push_back(code);
      return;
    }
    if (!g.changed) {
      touched.push_back(field.group);
      g.value = value;
      g.unknown = unknown;
    } else if (g.same) {
      g.same = sameValue(g);
    }
    field.next = g.first;
    g.first = code;
    ++g.changed;
  }

  template <typename Key, typename ReadWord>
  void refine(Key key, ReadWord readWord) {
    for (uint32_t id : touched) {
      Group &g = groups[id];
      if (g.changed == g.size && g.same) {
        ++g.changes;
        changed.push_back(g.first);
      } else {
        const uint32_t parent = g.node;
        const uint64_t prior = g.changes;
        const uint64_t value = g.value, unknown = g.unknown;
        g.size -= g.changed;
        uint32_t reuse = g.size ? none : id;
        if (g.size) {
          g.node = nodes.size();
          nodes.push_back({parent, nodes[parent].variable});
        }
        std::unordered_map<std::string, uint32_t> byValue;
        uint32_t common = none;
        for (uint32_t c = g.first; c != none; c = fields[c].next) {
          uint32_t *child = &common;
          if (!g.same)
            child = &byValue.try_emplace(key(c), none).first->second;
          if (*child == none) {
            if (reuse == none) {
              *child = groups.size();
              groups.emplace_back();
            } else {
              *child = reuse;
              reuse = none;
            }
            Group &subgroup = groups[*child];
            subgroup.changes = prior + 1;
            if (g.same) {
              subgroup.value = value;
              subgroup.unknown = unknown;
            } else {
              readWord(c, subgroup);
            }
            subgroup.node = nodes.size();
            nodes.push_back({parent, c});
            changed.push_back(c);
          }
          ++groups[*child].size;
          fields[c].group = *child;
        }
      }
      g.first = none;
      g.changed = 0;
      g.same = true;
    }
    touched.clear();
    ++samples;
  }

  // Descendants of a prefix occupy a contiguous span in DFS order. Replaying
  // one journal value fans out to these identifiers without storing a list of
  // every descendant at every ancestor (which can be quadratic).
  template <typename Identifier>
  Layout layout(bool separate, Identifier identifier) const {
    Layout result;
    result.physical.resize(fields.size());
    std::vector<uint32_t> rank(groups.size()), order(groups.size());
    for (uint32_t g = 0; g < groups.size(); ++g)
      order[g] = g;
    std::stable_sort(order.begin(), order.end(), [&](uint32_t a, uint32_t b) {
      return groups[a].changes > groups[b].changes;
    });
    for (uint32_t i = 0; i < order.size(); ++i)
      rank[order[i]] = i;
    std::vector<std::vector<uint32_t>> children(nodes.size()),
        ids(nodes.size());
    std::vector<uint32_t> work;
    for (uint32_t n = 0; n < nodes.size(); ++n) {
      if (nodes[n].parent == none)
        work.push_back(n);
      else
        children[nodes[n].parent].push_back(n);
    }
    for (uint32_t c = 0; c < fields.size(); ++c) {
      uint32_t g = fields[c].group;
      uint32_t id = separate ? fields[c].code : rank[g];
      result.physical[fields[c].code] = id;
      auto &leaf = ids[groups[g].node];
      if (separate || leaf.empty())
        leaf.push_back(id);
    }
    result.spans.resize(nodes.size());
    while (!work.empty()) {
      uint32_t n = work.back();
      work.pop_back();
      for (auto child : children[n])
        work.push_back(child);
      auto begin = static_cast<uint32_t>(result.codes.size());
      for (uint32_t id : ids[n])
        result.codes.push_back(identifier(id));
      result.spans[n] = {begin, static_cast<uint32_t>(result.codes.size())};
    }
    for (size_t i = nodes.size(); i--;) {
      for (auto child : children[i]) {
        result.spans[i].begin =
            std::min(result.spans[i].begin, result.spans[child].begin);
        result.spans[i].end =
            std::max(result.spans[i].end, result.spans[child].end);
      }
    }
    return result;
  }
};
} // namespace talos::runtime::vcd

#endif // TALOS_RUNTIME_LIB_VCDCOMPACT_H
