// Graph separation oracle for the finite-wave scheduling reference planner.
#include <algorithm>
#include <cstdint>
#include <limits>
#include <numeric>
#include <unordered_set>
#include <utility>
#include <vector>

#if defined(_WIN32)
#define RANK_API extern "C" __declspec(dllexport)
#else
#define RANK_API extern "C" __attribute__((visibility("default")))
#endif

namespace {
struct Edge {
  int target, weight, gate;
};
struct Frame {
  int node, next;
};

// Edges never move during a search. Disabling a cut or retry gate changes
// only a bitmap. SCC numbering is reverse topological (Tarjan pop order).
class RankGraph {
public:
  RankGraph(int n, const int *records, int count)
      : component(n), offsets(n + 1), edges(count), number(n), low(n), first(n),
        next(n), seen(n), parent(n), parentGate(n), levels(n) {
    int minGate = 0, maxGate = 0;
    for (int i = 0; i < count; ++i) {
      ++offsets[records[4 * i] + 1];
      minGate = std::min(minGate, records[4 * i + 3]);
      maxGate = std::max(maxGate, records[4 * i + 3]);
    }
    std::partial_sum(offsets.begin(), offsets.end(), offsets.begin());
    auto cursor = offsets;
    for (int i = 0; i < count; ++i) {
      const int *p = records + 4 * i;
      edges[cursor[p[0]]++] = {p[1], p[2], p[3]};
    }
    gateBase = minGate;
    disabled.resize(size_t(int64_t(maxGate) - minGate + 1));
    active.reserve(n);
    stack.reserve(n);
    queue.reserve(n);
  }

  void findComponents(const int *gates, int size) {
    std::fill(disabled.begin(), disabled.end(), 0);
    for (int i = 0; i < size; ++i) {
      auto index = int64_t(gates[i]) - gateBase;
      if (index >= 0 && size_t(index) < disabled.size())
        disabled[index] = 1;
    }
    std::fill(number.begin(), number.end(), -1);
    std::fill(component.begin(), component.end(), -1);
    int stamp = 0;
    groups = 0;
    auto enter = [&](int n) {
      number[n] = low[n] = stamp++;
      active.push_back(n);
      stack.push_back({n, offsets[n]});
    };
    for (int root = 0; root < int(number.size()); ++root) {
      if (number[root] >= 0)
        continue;
      enter(root);
      while (!stack.empty()) {
        Frame &frame = stack.back();
        int a = frame.node;
        if (frame.next != offsets[a + 1]) {
          const Edge &edge = edges[frame.next++];
          if (off(edge))
            continue;
          int b = edge.target;
          if (number[b] < 0)
            enter(b);
          else if (component[b] < 0)
            low[a] = std::min(low[a], number[b]);
          continue;
        }
        if (number[a] == low[a]) {
          int v;
          do {
            v = active.back();
            active.pop_back();
            component[v] = groups;
          } while (v != a);
          ++groups;
        }
        stack.pop_back();
        if (!stack.empty()) {
          int from = stack.back().node;
          low[from] = std::min(low[from], low[a]);
        }
      }
    }
  }

  // A forward-only schedule exists exactly when no strict edge lies on a
  // live cycle. Each such cycle must lose at least one of its optional gates.
  bool feasible(const int *gates, int size) {
    findComponents(gates, size);
    for (int a = 0; a < int(component.size()); ++a)
      for (int i = offsets[a]; i < offsets[a + 1]; ++i) {
        const Edge &e = edges[i];
        if (e.weight && !off(e) && component[a] == component[e.target])
          return false;
      }
    return true;
  }

  // A feasible incumbent has only zero-weight cycles. Every member of such
  // a cycle must keep the same rank when additional equalities are imposed.
  // Freeze the retry gates and contract these equalities once, then test
  // omissions of the incumbent's cut sites on the smaller exact graph.
  RankGraph *cutSubsetGraph(const int *gates, int size) {
    findComponents(gates, size);
    std::vector<int> records;
    for (int a = 0; a < int(component.size()); ++a)
      for (int i = offsets[a]; i < offsets[a + 1]; ++i) {
        const Edge &e = edges[i];
        int from = component[a], to = component[e.target];
        if (from == to || (e.gate < 0 && off(e)))
          continue;
        records.insert(records.end(),
                       {from, to, e.weight, off(e) ? e.gate : 0});
      }
    return new RankGraph(groups, records.data(), records.size() / 4);
  }

  int check(const int *gates, int size, int witnesses) {
    findComponents(gates, size);
    clauses.clear();
    std::fill_n(first.begin(), groups, -1);
    std::fill_n(levels.begin(), groups, 0);
    for (int a = int(component.size()) - 1; a >= 0; --a) {
      int g = component[a];
      next[a] = first[g];
      first[g] = a;
    }
    for (int g = groups - 1; g >= 0; --g) {
      int found = 0;
      for (int a = first[g]; a >= 0; a = next[a]) {
        for (int i = offsets[a]; i < offsets[a + 1]; ++i) {
          const Edge &edge = edges[i];
          if (off(edge))
            continue;
          int dest = component[edge.target];
          if (dest != g)
            levels[dest] = std::max(levels[dest], levels[g] + edge.weight);
          else if (edge.weight && found < witnesses) {
            if (!explain(a, edge, g))
              return -1;
            ++found;
          }
        }
      }
    }
    if (!clauses.empty())
      return 0;
    ranks.resize(component.size());
    for (size_t i = 0; i < ranks.size(); ++i)
      ranks[i] = levels[component[i]];
    return 1;
  }

  // The caller supplies a mixed-owner SCC from this exact graph.
  void writeCycle(const std::vector<int> &group, std::vector<int> &cycle) {
    for (int a : group)
      for (int j = offsets[a]; j < offsets[a + 1]; ++j) {
        const auto &edge = edges[j];
        int b = edge.target;
        if (!edge.weight || component[a] != component[b])
          continue;
        queue.clear();
        queue.push_back(b);
        parent[b] = b;
        ++search;
        seen[b] = search;
        for (size_t head = 0; seen[a] != search; ++head) {
          int v = queue[head];
          for (int i = offsets[v]; i < offsets[v + 1]; ++i) {
            int w = edges[i].target;
            if (component[w] != component[a] || seen[w] == search)
              continue;
            seen[w] = search;
            parent[w] = v;
            queue.push_back(w);
          }
        }
        cycle.push_back(a);
        for (int n = a;; n = parent[n]) {
          cycle.push_back(n);
          if (n == b)
            break;
        }
        std::reverse(cycle.begin() + 1, cycle.end());
        return;
      }
  }

  // Coalesce neighboring source pieces in a feasible witness. Moving an
  // equality class within the intersection of its live predecessor and
  // successor bounds preserves every hard dependency and retry barrier.
  // This only improves the incumbent: the SAT lower-bound search is unchanged.
  void compact() {
    const int n = int(ranks.size());
    std::vector<int> rep(n), reverseOffsets(n + 1), reverseEdges(edges.size());
    std::vector<std::vector<int>> members(n);
    std::iota(rep.begin(), rep.end(), 0);
    for (int a = 0; a < n; ++a)
      members[a].push_back(a);
    auto leader = [&](int a) {
      while (rep[a] != a) {
        rep[a] = rep[rep[a]];
        a = rep[a];
      }
      return a;
    };
    auto join = [&](int a, int b, int value) {
      if (members[a].size() < members[b].size())
        std::swap(a, b);
      members[a].insert(members[a].end(), members[b].begin(), members[b].end());
      members[b].clear();
      rep[b] = a;
      ranks[a] = value;
    };
    std::vector<std::pair<int, int>> candidates;
    for (int a = 0; a < n; ++a) {
      for (int i = offsets[a]; i < offsets[a + 1]; ++i) {
        const auto &e = edges[i];
        if (!off(e))
          ++reverseOffsets[e.target + 1];
        if (e.gate <= 0)
          continue;
        int lhs = leader(a), rhs = leader(e.target);
        if (lhs == rhs)
          continue;
        if (ranks[lhs] == ranks[rhs])
          join(lhs, rhs, ranks[lhs]);
        else
          candidates.emplace_back(a, e.target);
      }
    }
    std::partial_sum(reverseOffsets.begin(), reverseOffsets.end(),
                     reverseOffsets.begin());
    auto cursor = reverseOffsets;
    for (int a = 0; a < n; ++a)
      for (int i = offsets[a]; i < offsets[a + 1]; ++i)
        if (!off(edges[i]))
          reverseEdges[cursor[edges[i].target]++] = i;
    // Recover the source of an incoming edge without a per-visit CSR search.
    std::vector<int> sources(edges.size());
    for (int a = 0; a < n; ++a)
      std::fill(sources.begin() + offsets[a], sources.begin() + offsets[a + 1],
                a);
    for (bool changed = true; changed;) {
      changed = false;
      for (auto [from, to] : candidates) {
        int a = leader(from), b = leader(to);
        if (a == b)
          continue;
        int lowBound = 0, highBound = n;
        for (int part : {a, b}) {
          for (int v : members[part]) {
            for (int i = offsets[v]; i < offsets[v + 1]; ++i) {
              const auto &e = edges[i];
              if (off(e))
                continue;
              int dest = leader(e.target);
              if (dest != a && dest != b)
                highBound = std::min(highBound, ranks[dest] - e.weight);
              else if (e.weight)
                highBound = -1;
            }
            for (int j = reverseOffsets[v]; j < reverseOffsets[v + 1]; ++j) {
              int i = reverseEdges[j], source = leader(sources[i]);
              if (source != a && source != b)
                lowBound = std::max(lowBound, ranks[source] + edges[i].weight);
            }
            if (lowBound > highBound)
              break;
          }
          if (lowBound > highBound)
            break;
        }
        if (lowBound <= highBound) {
          join(a, b, std::clamp(ranks[a], lowBound, highBound));
          changed = true;
        }
      }
    }
    for (int a = 0; a < n; ++a)
      ranks[a] = ranks[leader(a)];
  }

  std::vector<int> component, clauses, ranks;
  int groups = 0;

private:
  bool off(const Edge &e) const { return disabled[e.gate - gateBase]; }

  bool explain(int source, const Edge &edge, int group) {
    // Stamps avoid clearing the traversal arrays for each cycle witness.
    if (++search == 0) {
      std::fill(seen.begin(), seen.end(), 0);
      ++search;
    }
    int target = edge.target;
    seen[target] = search;
    queue.clear();
    queue.push_back(target);
    for (size_t i = 0; seen[source] != search; ++i) {
      int a = queue[i];
      for (int j = offsets[a]; j < offsets[a + 1]; ++j) {
        const Edge &e = edges[j];
        if (off(e) || component[e.target] != group || seen[e.target] == search)
          continue;
        seen[e.target] = search;
        parent[e.target] = a;
        parentGate[e.target] = e.gate;
        queue.push_back(e.target);
      }
    }
    size_t start = clauses.size();
    if (edge.gate)
      clauses.push_back(edge.gate);
    for (int at = source; at != target; at = parent[at])
      if (parentGate[at])
        clauses.push_back(parentGate[at]);
    if (clauses.size() == start)
      return false;
    clauses.push_back(0);
    return true;
  }

  std::vector<int> offsets;
  std::vector<Edge> edges;
  std::vector<int> number, low, first, next;
  std::vector<uint32_t> seen;
  std::vector<int> parent, parentGate, levels, active, queue;
  std::vector<Frame> stack;
  std::vector<uint8_t> disabled;
  uint32_t search = 0;
  int gateBase = 0;
};
struct Pair {
  int from, to;
};
struct Dependency {
  int from, to;
  bool hard;
};

// Both searches use the same immutable model. Build the two CSR topologies
// once, remapping only processes that share a coarse component.
class Topology {
public:
  Topology(int n, int ownerCount, const int *ownerOf, const int *sources,
           int ns, const int *dependencies, int nd, const int *hard, int nh)
      : owners(ownerOf, ownerOf + n), byOwner(ownerCount), kernel(n, -1),
        coarse(ownerCount) {
    for (int i = 0; i < n; ++i)
      byOwner[owners[i]].push_back(i);
    std::vector<int> fine, process;
    auto add = [](auto &edges, int a, int b, int weight) {
      edges.insert(edges.end(), {a, b, weight, 0});
    };
    for (int i = 0; i < ns; ++i) {
      int a = sources[2 * i], b = sources[2 * i + 1];
      control.push_back({a, b});
      add(fine, a, b, 0);
    }
    std::unordered_set<uint64_t> hardPairs;
    auto key = [](int a, int b) {
      return (uint64_t(uint32_t(a)) << 32) | uint32_t(b);
    };
    for (int i = 0; i < nh; ++i)
      hardPairs.insert(key(hard[2 * i], hard[2 * i + 1]));
    for (int i = 0; i < nd; ++i) {
      int a = dependencies[2 * i], b = dependencies[2 * i + 1];
      required.push_back({a, b, hardPairs.count(key(a, b)) != 0});
      add(fine, a, b, 1);
      add(process, owners[a], owners[b], 0);
    }
    {
      RankGraph graph(n, fine.data(), fine.size() / 4);
      graph.findComponents(nullptr, 0);
      std::vector<int> firstOwner(graph.groups, -1);
      std::vector<bool> mixed(graph.groups, false);
      for (int v = 0; v < n; ++v) {
        int c = graph.component[v];
        if (firstOwner[c] < 0)
          firstOwner[c] = owners[v];
        else if (firstOwner[c] != owners[v])
          mixed[c] = true;
      }
      std::vector<int> id(graph.groups, -1);
      for (int c = graph.groups - 1; c >= 0; --c)
        if (mixed[c])
          id[c] = kernelCount++;
      std::vector<std::vector<int>> groups(kernelCount);
      for (int v = 0; v < n; ++v) {
        kernel[v] = id[graph.component[v]];
        if (kernel[v] >= 0)
          groups[kernel[v]].push_back(v);
      }
      for (const auto &group : groups) {
        kernels.insert(kernels.end(), group.begin(), group.end());
        kernels.push_back(-1);
      }
      if (kernelCount)
        graph.writeCycle(groups.front(), cycle);
    }
    if (!kernelCount)
      return;
    RankGraph graph(ownerCount, process.data(), process.size() / 4);
    graph.findComponents(nullptr, 0);
    ownerGroups.resize(graph.groups);
    for (int p = 0; p < ownerCount; ++p) {
      coarse[p] = graph.groups - 1 - graph.component[p];
      ownerGroups[coarse[p]].push_back(p);
    }
    std::vector<bool> boundary(n, false);
    for (const auto &e : control)
      if (kernel[e.from] != kernel[e.to])
        boundary[e.to] = true;
    for (int v = 0; v < n; ++v)
      if (boundary[v])
        mandatory.push_back(v);
  }

  // When ranking first, retain intra-process equality across the original
  // SCC perimeter. The final indivisible slices determine the settle groups.
  void rankFirst() {
    isolateOperations = false;
    mandatory.clear();
  }

  RankGraph *build(bool ownersOnly) {
    auto &nodes = ownersOnly ? kernelNodes : jointNodes;
    nodes.clear();
    if (ownersOnly) {
      for (int i = 0; i < int(kernel.size()); ++i)
        if (kernel[i] >= 0)
          nodes.push_back(i);
    } else {
      for (const auto &group : ownerGroups)
        if (group.size() > 1)
          for (int owner : group)
            nodes.insert(nodes.end(), byOwner[owner].begin(),
                         byOwner[owner].end());
    }
    std::vector<int> local(kernel.size(), -1), records;
    for (int i = 0; i < int(nodes.size()); ++i)
      local[nodes[i]] = i;
    int count = nodes.size();
    bool barriers = !ownersOnly && isolateOperations;
    auto enter = [&](int n) {
      return barriers && kernel[n] >= 0 ? count + 2 * kernel[n] : local[n];
    };
    auto exit = [&](int n) {
      return barriers && kernel[n] >= 0 ? count + 2 * kernel[n] + 1 : local[n];
    };
    auto arc = [&](int a, int b, int w, int g = 0) {
      records.insert(records.end(), {a, b, w, g});
    };
    std::vector<bool> boundary(kernel.size(), false);
    if (barriers) {
      for (int n : mandatory)
        boundary[n] = true;
      for (int n : nodes)
        if (kernel[n] >= 0) {
          arc(enter(n), local[n], 0);
          arc(local[n], exit(n), 0);
        }
    }
    for (auto [a, b] : control) {
      if (local[a] < 0 || local[b] < 0)
        continue;
      if (ownersOnly) {
        if (kernel[a] == kernel[b])
          arc(local[a], local[b], 0);
      } else {
        arc(local[a], local[b], 0);
        if (!boundary[b])
          arc(local[b], local[a], 0, b + 1);
        if (barriers && kernel[a] != kernel[b])
          arc(exit(a), enter(b), 1);
      }
    }
    for (auto [a, b, hard] : required) {
      if (local[a] < 0 || local[b] < 0 ||
          coarse[owners[a]] != coarse[owners[b]])
        continue;
      if (kernel[a] >= 0 && kernel[a] == kernel[b])
        arc(local[a], local[b], 1, hard ? 0 : -1 - owners[b]);
      else if (!ownersOnly)
        arc(exit(a), enter(b), 1);
    }
    return new RankGraph(count + (barriers ? 2 * kernelCount : 0),
                         records.data(), records.size() / 4);
  }

  void expand(const RankGraph &graph) {
    fullRanks.assign(owners.size(), 0);
    for (size_t i = 0; i < jointNodes.size(); ++i)
      fullRanks[jointNodes[i]] = graph.ranks[i];
    int offset = 0;
    for (const auto &group : ownerGroups) {
      int high = offset;
      for (int p : group)
        for (int v : byOwner[p]) {
          fullRanks[v] += offset;
          high = std::max(high, fullRanks[v]);
        }
      offset = high + 1;
    }
  }

  // Recheck the full original edge inventory, including the edges outside the
  // compact search graph, before exposing an incumbent to the caller.
  bool verify() {
    cutSites.clear();
    backward.clear();
    std::vector<bool> cut(owners.size(), false);
    std::vector<int> first(kernelCount, std::numeric_limits<int>::max()),
        last(kernelCount, -1);
    for (size_t n = 0; n < kernel.size(); ++n) {
      int k = kernel[n];
      if (k >= 0) {
        first[k] = std::min(first[k], fullRanks[n]);
        last[k] = std::max(last[k], fullRanks[n]);
      }
    }
    auto orderedAcrossKernels = [&](int a, int b) {
      if (!isolateOperations || kernel[a] == kernel[b])
        return true;
      int from = kernel[a] < 0 ? fullRanks[a] : last[kernel[a]];
      int to = kernel[b] < 0 ? fullRanks[b] : first[kernel[b]];
      return from < to;
    };
    for (auto [a, b] : control) {
      if (fullRanks[a] > fullRanks[b] || !orderedAcrossKernels(a, b))
        return false;
      if (fullRanks[a] < fullRanks[b])
        cut[b] = true;
    }
    for (int i = 0; i < int(cut.size()); ++i)
      if (cut[i])
        cutSites.push_back(i);
    for (auto [a, b, hard] : required) {
      if (!orderedAcrossKernels(a, b))
        return false;
      if (fullRanks[a] >= fullRanks[b]) {
        if (hard || kernel[b] < 0 || kernel[a] != kernel[b])
          return false;
        backward.push_back(a);
        backward.push_back(b);
      }
    }
    return true;
  }
  std::vector<int> kernels, cycle, mandatory, fullRanks, cutSites, backward;

private:
  std::vector<int> owners;
  std::vector<std::vector<int>> byOwner, ownerGroups;
  std::vector<int> kernel, coarse, kernelNodes, jointNodes;
  std::vector<Pair> control;
  std::vector<Dependency> required;
  int kernelCount = 0;
  bool isolateOperations = true;
};
} // namespace

RANK_API void talos_rank_free(RankGraph *graph) { delete graph; }
RANK_API RankGraph *talos_rank_cut_subset(RankGraph *g, const int *gates,
                                          int size) {
  return g->cutSubsetGraph(gates, size);
}
RANK_API int talos_rank_feasible(RankGraph *g, const int *gates, int size) {
  return g->feasible(gates, size);
}
RANK_API int talos_rank_check(RankGraph *graph, const int *disabled, int count,
                              int witnesses, int compact, const int **data,
                              int *size) {
  int status = graph->check(disabled, count, witnesses);
  if (status == 1 && compact)
    graph->compact();
  const auto &v = graph->clauses;
  *data = v.data();
  *size = int(v.size());
  return status;
}

RANK_API Topology *talos_rank_model(int n, int owners, const int *owner,
                                    const int *control, int nc,
                                    const int *required, int nr,
                                    const int *hard, int nh) {
  return new Topology(n, owners, owner, control, nc, required, nr, hard, nh);
}
RANK_API void talos_rank_model_free(Topology *p) { delete p; }
RANK_API void talos_rank_model_rank_first(Topology *p) { p->rankFirst(); }
RANK_API RankGraph *talos_rank_model_graph(Topology *p, int ownersOnly) {
  return p->build(ownersOnly != 0);
}
RANK_API int talos_rank_expand(Topology *p, RankGraph *graph) {
  p->expand(*graph);
  return p->verify();
}
RANK_API const int *talos_rank_model_data(Topology *p, int field, int *size) {
  const std::vector<int> *values[] = {&p->kernels,   &p->cycle,
                                      &p->mandatory, &p->fullRanks,
                                      &p->cutSites,  &p->backward};
  auto &v = *values[field];
  *size = int(v.size());
  return v.data();
}
