#include "SupplyNetwork.h"
#include "llvm/Support/ErrorHandling.h"
#include <algorithm>
#include <limits>
#include <numeric>
#include <queue>

using namespace mlir;
using llvm::StringRef;
namespace talos {
namespace {
struct Groups {
  std::vector<unsigned> parents;
  Groups(unsigned count) : parents(count) {
    std::iota(parents.begin(), parents.end(), 0);
  }
  unsigned find(unsigned id) {
    while (parents[id] != id) {
      parents[id] = parents[parents[id]];
      id = parents[id];
    }
    return id;
  }
  void join(unsigned a, unsigned b) { parents[find(a)] = find(b); }
};
bool within(StringRef path, StringRef prefix) {
  return path == prefix || (path.starts_with(prefix) &&
                            path.drop_front(prefix.size()).starts_with('.'));
}
} // namespace
std::string absoluteSupplyHandle(StringRef path) {
  std::string result = "/" + path.str();
  std::replace(result.begin(), result.end(), '.', '/');
  return result;
}
LogicalResult bindSupply(
    const SupplyObject &net, StringRef port, SupplyBindings &bindings,
    llvm::function_ref<void(const llvm::Twine &)> report,
    llvm::function_ref<bool(const SupplyObject &, const SupplyObject &)> same) {
  // IEEE 1801-2018 4.5.4.3/6.14: each side permits one connection.
  // A net in the same scope connects LowConn; a port in a descendant scope
  // connects HighConn. Siblings and an ancestor port are not legal targets.
  StringRef netScope = net.scope, portScope = port.rsplit('.').first;
  if (netScope != portScope && !within(portScope, netScope)) {
    report("supply port must be in the net's scope or a descendant scope: " +
           port);
    return failure();
  }
  bool high = netScope != portScope;
  auto [found, inserted] =
      bindings.emplace(std::make_pair(port.str(), high), net);
  if (!inserted && found->second != net &&
      (!same || !same(found->second, net))) {
    report("supply port side is already connected: " + port);
    return failure();
  }
  return success();
}
FailureOr<ResolvedSupplies>
resolveSupplies(const std::set<std::string> &nets, const SupplyPorts &ports,
                const SupplyFunctions &functions,
                const SupplyBindings &bindings,
                const SupplyEquivalences &equivalences,
                llvm::function_ref<void(const llvm::Twine &)> report) {
  std::map<std::string, unsigned> netIDs, portIDs, functionIDs;
  uint64_t size = uint64_t(nets.size()) + ports.size() + functions.size();
  if (size > std::numeric_limits<unsigned>::max()) {
    report("supply network exceeds the supported object count");
    return failure();
  }
  unsigned count = 0;
  for (auto &net : nets)
    netIDs[net] = count++;
  for (auto &[name, port] : ports)
    portIDs[name] = count++;
  for (auto &[name, scope] : functions)
    functionIDs[name] = count++;
  auto node = [&](const SupplyObject &object) {
    switch (object.kind) {
    case SupplyObject::Net:
      return netIDs.at(object.path);
    case SupplyObject::Port:
      return portIDs.at(object.path);
    case SupplyObject::Function:
      return functionIDs.at(object.path);
    }
    llvm_unreachable("unknown supply object kind");
  };
  for (auto &[name, port] : ports)
    if (port.switchOutput && bindings.count({name, false})) {
      report("internal power-switch output connections are not implemented: " +
             name);
      return failure();
    }
  for (auto &[side, net] : bindings)
    if (ports.at(side.first).direction == SupplyPort::InOut) {
      // 4.5.4.2/9.1: inout boundary sources must be counted before
      // electrical equivalence is collapsed. Do not merge away an extra
      // driver on an unresolved net until that source model is implemented.
      report("inout supply connections are not implemented: " + side.first);
      return failure();
    }
  Groups aliases(count), connected(count);
  // IEEE 1801-2018 4.5.5.2(f)/4.5.5.3/6.10: function bindings and set
  // associations establish electrical equivalence, including bindings added
  // after an association. They do not create extra physical supply drivers.
  for (auto &[a, b] : equivalences) {
    aliases.join(node(a), node(b));
    connected.join(node(a), node(b));
  }
  for (auto &[side, net] : bindings) {
    unsigned p = portIDs.at(side.first), n = node(net);
    connected.join(p, n);
  }
  // IEEE 1801-2018 4.5.5.2/9.1: electrically equivalent unresolved supplies
  // share one root. Preserve the directional source/load graph until each
  // connected group has been checked to have exactly one source.
  std::set<std::pair<unsigned, unsigned>> edges;
  for (auto &[side, net] : bindings) {
    unsigned p = aliases.find(portIDs.at(side.first)),
             n = aliases.find(node(net));
    if (p == n)
      continue;
    bool portDrives =
        (ports.at(side.first).direction == SupplyPort::In) != side.second;
    edges.emplace(portDrives ? p : n, portDrives ? n : p);
  }
  std::vector<std::vector<unsigned>> outgoing(count);
  std::vector<unsigned> incoming(count, 0);
  for (auto [from, to] : edges) {
    outgoing[from].push_back(to);
    ++incoming[to];
  }
  // Count physical sources before collapsing aliases. Otherwise associating
  // two input ports could erase an unresolved multiple-driver error
  // (4.5.4.2/9.1). Unbound functions acquire one fallback root per final
  // subnet, not one independent driver per declaration (6.26.2).
  std::map<unsigned, std::vector<unsigned>> sources;
  for (auto &[name, port] : ports) {
    bool source = port.direction == SupplyPort::In
                      ? !bindings.count({name, true})
                      : !bindings.count({name, false});
    if (source)
      sources[connected.find(portIDs.at(name))].push_back(portIDs.at(name));
  }
  unsigned components = 0;
  std::map<unsigned, std::vector<unsigned>> fallback;
  std::queue<unsigned> pending;
  for (unsigned i = 0; i < count; ++i) {
    if (aliases.find(i) != i)
      continue;
    ++components;
    if (incoming[i] == 0) {
      pending.push(i);
      fallback[connected.find(i)].push_back(i);
    }
  }
  unsigned visited = 0;
  while (!pending.empty()) {
    unsigned from = pending.front();
    pending.pop();
    ++visited;
    for (unsigned to : outgoing[from])
      if (--incoming[to] == 0)
        pending.push(to);
  }
  if (visited != components) {
    report("cyclic directional supply network has no supported root driver");
    return failure();
  }
  std::map<unsigned, unsigned> rootIDs;
  ResolvedSupplies result;
  std::map<unsigned, std::vector<unsigned>> members;
  std::set<unsigned> switchSources;
  for (auto &[name, port] : ports)
    if (port.switchOutput)
      switchSources.insert(portIDs.at(name));
  for (unsigned i = 0; i < count; ++i) {
    sources.try_emplace(connected.find(i));
    members[connected.find(i)].push_back(aliases.find(i));
  }
  std::vector<unsigned> reached(count, 0);
  for (auto &[group, roots] : sources) {
    if (roots.empty())
      roots = fallback[group];
    if (roots.size() > 1) {
      report("multiple sources drive one unresolved supply group");
      return failure();
    }
    if (!roots.empty()) {
      unsigned generation = result.roots.size() + 1;
      pending.push(aliases.find(roots.front()));
      reached[pending.front()] = generation;
      while (!pending.empty()) {
        unsigned from = pending.front();
        pending.pop();
        for (unsigned to : outgoing[from])
          if (reached[to] != generation) {
            reached[to] = generation;
            pending.push(to);
          }
      }
      for (unsigned n : members.at(group))
        if (reached[n] != generation) {
          // 9.1(e): do not infer a reverse drive through an input/output
          // port. This slice requires source-to-load reachability throughout
          // an associated directional network rather than resolving it.
          report(
              "supply source cannot drive the associated directional network");
          return failure();
        }
    }
    unsigned id = result.roots.size();
    rootIDs[group] = id;
    result.roots.push_back({});
    if (!roots.empty() && switchSources.count(roots.front()))
      result.roots.back().writable = false;
  }
  auto handles = [&](StringRef name, unsigned id, bool port) {
    std::string absolute = absoluteSupplyHandle(name);
    // IEEE 1801-2018 10.3.2.2.3: unqualified same-name lookup prefers ports.
    if (port)
      result.handles[absolute] = id;
    else
      result.handles.try_emplace(absolute, id);
    result.handles[absolute + (port ? "@upfSupplyPortT" : "@upfSupplyNetT")] =
        id;
  };
  for (auto &[name, node] : netIDs) {
    unsigned id = rootIDs.at(connected.find(node));
    result.nets[name] = id;
    handles(name, id, false);
  }
  for (auto &[name, node] : portIDs) {
    unsigned id = rootIDs.at(connected.find(node));
    result.ports[name] = id;
    handles(name, id, true);
  }
  for (auto &[name, node] : functionIDs) {
    unsigned id = rootIDs.at(connected.find(node));
    result.functions[name] = id;
    // Dots are UPF object fields, not hierarchy separators (5.3.3.3/.5).
    result.handles[name] = id;
    result.handles[name + "@upfSupplyNetT"] = id;
  }
  return result;
}
} // namespace talos
