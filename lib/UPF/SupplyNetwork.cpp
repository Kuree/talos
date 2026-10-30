#include "SupplyNetwork.h"
#include <algorithm>
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
LogicalResult bindSupply(StringRef net, StringRef port,
                         SupplyBindings &bindings,
                         llvm::function_ref<void(const llvm::Twine &)> report) {
  // IEEE 1801-2018 4.5.4.3/6.14: each side permits one connection.
  // A net in the same scope connects LowConn; a port in a descendant scope
  // connects HighConn. Siblings and an ancestor port are not legal targets.
  StringRef netScope = net.rsplit('.').first,
            portScope = port.rsplit('.').first;
  if (netScope != portScope && !within(portScope, netScope)) {
    report("supply port must be in the net's scope or a descendant scope: " +
           port);
    return failure();
  }
  bool high = netScope != portScope;
  auto [found, inserted] =
      bindings.emplace(std::make_pair(port.str(), high), net.str());
  if (!inserted && found->second != net) {
    report("supply port side is already connected: " + port);
    return failure();
  }
  return success();
}
FailureOr<ResolvedSupplies>
resolveSupplies(const std::set<std::string> &nets, const SupplyPorts &ports,
                const SupplyBindings &bindings,
                llvm::function_ref<void(const llvm::Twine &)> report) {
  std::map<std::string, unsigned> netIDs, portIDs;
  unsigned count = 0;
  for (auto &net : nets)
    netIDs[net] = count++;
  for (auto &[name, port] : ports)
    portIDs[name] = count++;
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
  Groups connected(count);
  for (auto &[side, net] : bindings) {
    unsigned p = portIDs.at(side.first), n = netIDs.at(net);
    connected.join(p, n);
  }
  // IEEE 1801-2018 4.5.5.2/9.1: electrically equivalent unresolved supplies
  // share one root. Preserve the directional source/load graph until each
  // connected group has been checked to have exactly one source.
  std::set<std::pair<unsigned, unsigned>> edges;
  for (auto &[side, net] : bindings) {
    unsigned p = portIDs.at(side.first), n = netIDs.at(net);
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
  std::map<unsigned, std::vector<unsigned>> sources;
  std::queue<unsigned> pending;
  for (unsigned i = 0; i < count; ++i) {
    if (incoming[i] == 0) {
      pending.push(i);
      sources[connected.find(i)].push_back(i);
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
  if (visited != count) {
    report("cyclic directional supply network has no supported root driver");
    return failure();
  }
  std::map<unsigned, unsigned> rootIDs;
  ResolvedSupplies result;
  for (auto &[group, roots] : sources) {
    if (roots.size() != 1) {
      report("multiple sources drive one unresolved supply group");
      return failure();
    }
    unsigned id = result.roots.size();
    rootIDs[group] = id;
    result.roots.push_back({});
    for (auto &[name, port] : ports)
      if (port.switchOutput && portIDs.at(name) == roots[0])
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
  return result;
}
} // namespace talos
