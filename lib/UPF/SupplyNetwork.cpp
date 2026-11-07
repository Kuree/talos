#include "SupplyNetwork.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"
#include <algorithm>
#include <limits>
#include <optional>
#include <queue>

using namespace mlir;
using llvm::StringRef;
namespace talos {
namespace {
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
FailureOr<SupplyAliasClasses> classifySupplyAliases(
    const std::set<std::string> &nets, const SupplyPorts &ports,
    const SupplyFunctions &functions, const SupplyBindings &bindings,
    const SupplyEquivalences &equivalences,
    llvm::function_ref<void(const llvm::Twine &)> report) {
  if (nets.size() + ports.size() + functions.size() + bindings.size() +
          equivalences.size() >
      1048576) {
    report("supply usage inference exceeds 1048576 work units");
    return failure();
  }
  SupplyAliasClasses result;
  for (const auto &name : nets)
    result.emplace(std::pair{SupplyObject::Net, name}, result.size());
  for (const auto &[name, port] : ports)
    result.emplace(std::pair{SupplyObject::Port, name}, result.size());
  for (const auto &[name, scope] : functions)
    result.emplace(std::pair{SupplyObject::Function, name}, result.size());
  llvm::IntEqClasses groups(result.size());
  auto id = [&](const SupplyObject &object) {
    return result.at({object.kind, object.path});
  };
  for (const auto &[a, b] : equivalences)
    groups.join(id(a), id(b));
  for (const auto &[side, net] : bindings)
    groups.join(result.at({SupplyObject::Port, side.first}), id(net));
  groups.compress();
  for (auto &[name, value] : result)
    value = groups[value];
  return result;
}
FailureOr<ResolvedSupplies>
resolveSupplies(const std::set<std::string> &nets, const SupplyPorts &ports,
                const SupplyFunctions &functions,
                const SupplyBindings &bindings,
                const SupplyEquivalences &equivalences,
                llvm::function_ref<void(const llvm::Twine &)> report,
                const SupplyEquivalences &declaredElectrical) {
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
  llvm::IntEqClasses aliases(count), connected(count), sourceIdentity(count);
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
  // Connectivity aliases do not prove independent external ports are one
  // source. An explicit 6.44 declaration can provide that missing outside-
  // design connection. Resolve its endpoints against the ORIGINAL directed
  // graph, rather than blessing every source in a newly merged component.
  if (!declaredElectrical.empty()) {
    std::vector<std::vector<unsigned>> upstream(count), physical(count);
    std::set<unsigned> sourcePorts, computedPorts;
    for (const auto &[name, port] : ports) {
      bool source = port.direction == SupplyPort::In
                        ? !bindings.count({name, true})
                        : !bindings.count({name, false});
      if (source) {
        unsigned id = portIDs.at(name);
        sourcePorts.insert(id);
        physical[aliases.findLeader(id)].push_back(id);
        if (port.switchOutput)
          computedPorts.insert(id);
      }
    }
    for (const auto &[side, net] : bindings) {
      unsigned p = aliases.findLeader(portIDs.at(side.first));
      unsigned n = aliases.findLeader(node(net));
      if (p == n)
        continue;
      bool portDrives =
          (ports.at(side.first).direction == SupplyPort::In) != side.second;
      upstream[portDrives ? n : p].push_back(portDrives ? p : n);
    }
    // A declaration cannot make a source-free directional cycle into an
    // external fallback source merely by collapsing the cycle's endpoints.
    std::vector<std::vector<unsigned>> downstream(count);
    std::vector<unsigned> indegree(count);
    std::queue<unsigned> ready;
    unsigned vertices = 0, processed = 0;
    for (unsigned id = 0; id != count; ++id) {
      if (aliases.findLeader(id) != id)
        continue;
      ++vertices;
      indegree[id] = upstream[id].size();
      if (!indegree[id])
        ready.push(id);
      for (unsigned parent : upstream[id])
        downstream[parent].push_back(id);
    }
    while (!ready.empty()) {
      unsigned id = ready.front();
      ready.pop();
      ++processed;
      for (unsigned next : downstream[id])
        if (--indegree[next] == 0)
          ready.push(next);
    }
    if (processed != vertices) {
      report("cyclic directional supply network has no supported root driver");
      return failure();
    }
    size_t work = 0;
    auto origins = [&](unsigned id) -> std::optional<std::set<unsigned>> {
      if (sourcePorts.count(id))
        return std::set<unsigned>{id};
      std::set<unsigned> result, seen;
      std::vector<unsigned> pending{aliases.findLeader(id)};
      while (!pending.empty()) {
        unsigned current = pending.back();
        pending.pop_back();
        if (!seen.insert(current).second)
          continue;
        size_t cost = 1 + physical[current].size() + upstream[current].size();
        if (cost > 1048576 - work)
          return std::nullopt;
        work += cost;
        result.insert(physical[current].begin(), physical[current].end());
        pending.insert(pending.end(), upstream[current].begin(),
                       upstream[current].end());
      }
      return result;
    };
    // Keep original endpoint identities separate from connectivity aliases.
    // A chain through an unbound abstraction may identify external sources;
    // ordinary connections must not identify an unrelated third source.
    std::map<unsigned, std::set<unsigned>> originFacts;
    for (const auto &[a, b] : declaredElectrical) {
      sourceIdentity.join(node(a), node(b));
      for (unsigned endpoint : {node(a), node(b)}) {
        if (originFacts.count(endpoint))
          continue;
        auto sources = origins(endpoint);
        if (!sources) {
          report(
              "declared electrical source analysis exceeds 1048576 work units");
          return failure();
        }
        originFacts.emplace(endpoint, std::move(*sources));
      }
    }
    bool changed;
    do {
      changed = false;
      for (const auto &[endpoint, origins] : originFacts) {
        if (origins.size() + 1 > 1048576 - work) {
          report(
              "declared electrical source analysis exceeds 1048576 work units");
          return failure();
        }
        work += origins.size() + 1;
        std::set<unsigned> identities;
        for (unsigned source : origins)
          identities.insert(sourceIdentity.findLeader(source));
        if (identities.size() == 1 &&
            sourceIdentity.findLeader(endpoint) != *identities.begin()) {
          sourceIdentity.join(endpoint, *identities.begin());
          changed = true;
        }
      }
    } while (changed);
    for (const auto &[endpoint, origins] : originFacts) {
      std::set<unsigned> identities;
      for (unsigned source : origins)
        identities.insert(sourceIdentity.findLeader(source));
      if (identities.size() > 1) {
        report("declared electrical source equivalence requires unambiguous "
               "upstream origins");
        return failure();
      }
    }
    std::map<unsigned, std::set<unsigned>> provenSources;
    for (unsigned source : sourcePorts)
      provenSources[sourceIdentity.findLeader(source)].insert(source);
    for (const auto &[identity, sources] : provenSources)
      if (sources.size() > 1 && llvm::any_of(sources, [&](unsigned source) {
            return computedPorts.count(source);
          })) {
        report("declared electrical equivalence merges distinct computed "
               "switch supply sources");
        return failure();
      }
    for (const auto &[a, b] : declaredElectrical) {
      aliases.join(node(a), node(b));
      connected.join(node(a), node(b));
    }
  }
  // Flatten closed relations once before the per-object walks. LLVM's
  // uncompressed read API otherwise follows parent chains repeatedly.
  if (count) {
    for (auto *groups : {&aliases, &connected, &sourceIdentity}) {
      groups->compress();
      groups->uncompress();
    }
  }
  // IEEE 1801-2018 4.5.5.2/9.1: electrically equivalent unresolved supplies
  // share one root. Preserve the directional source/load graph until each
  // connected group has been checked to have exactly one source.
  std::set<std::pair<unsigned, unsigned>> edges;
  for (auto &[side, net] : bindings) {
    unsigned p = aliases.findLeader(portIDs.at(side.first)),
             n = aliases.findLeader(node(net));
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
      sources[connected.findLeader(portIDs.at(name))].push_back(
          portIDs.at(name));
  }
  unsigned components = 0;
  std::map<unsigned, std::vector<unsigned>> fallback;
  std::queue<unsigned> pending;
  for (unsigned i = 0; i < count; ++i) {
    if (aliases.findLeader(i) != i)
      continue;
    ++components;
    if (incoming[i] == 0) {
      pending.push(i);
      fallback[connected.findLeader(i)].push_back(i);
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
    sources.try_emplace(connected.findLeader(i));
    members[connected.findLeader(i)].push_back(aliases.findLeader(i));
  }
  std::vector<unsigned> reached(count, 0);
  std::set<unsigned> concreteRoots;
  for (auto &[name, id] : netIDs)
    concreteRoots.insert(aliases.findLeader(id));
  for (auto &[group, roots] : sources) {
    bool explicitSource = !roots.empty();
    if (roots.empty())
      roots = fallback[group];
    std::set<unsigned> identities;
    for (unsigned source : roots)
      identities.insert(sourceIdentity.findLeader(source));
    if (identities.size() > 1) {
      report("multiple sources drive one unresolved supply group");
      return failure();
    }
    if (!roots.empty()) {
      unsigned generation = result.roots.size() + 1;
      for (unsigned source : roots) {
        unsigned start = aliases.findLeader(source);
        if (reached[start] == generation)
          continue;
        pending.push(start);
        reached[start] = generation;
      }
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
    result.roots.back().explicitSource =
        explicitSource ||
        (!roots.empty() &&
         concreteRoots.count(aliases.findLeader(roots.front())));
    if (llvm::any_of(roots,
                     [&](unsigned root) { return switchSources.count(root); }))
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
    unsigned id = rootIDs.at(connected.findLeader(node));
    result.nets[name] = id;
    handles(name, id, false);
  }
  for (auto &[name, node] : portIDs) {
    unsigned id = rootIDs.at(connected.findLeader(node));
    result.ports[name] = id;
    handles(name, id, true);
  }
  for (auto &[name, node] : functionIDs) {
    unsigned id = rootIDs.at(connected.findLeader(node));
    result.functions[name] = id;
    // Dots are UPF object fields, not hierarchy separators (5.3.3.3/.5).
    result.handles[name] = id;
    result.handles[name + "@upfSupplyNetT"] = id;
  }
  return result;
}
} // namespace talos
