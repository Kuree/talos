#include "SupplyRelations.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringMap.h"
#include <queue>

using namespace mlir;
namespace talos {
LogicalResult validateUPFCompositeDomains(ModuleOp module,
                                          const SupplyRelations &relations) {
  if (module.getOps<upf::UPFCompositeDomainOp>().empty())
    return success();
  struct Node {
    Operation *domain;
    FlatSymbolRefAttr primary;
    SmallVector<unsigned> children;
    unsigned incoming = 0;
  };
  SmallVector<Node> nodes;
  llvm::StringMap<unsigned> indices;
  size_t work = 0;
  auto charge = [&](size_t count = 1) {
    if (count > 1048576 - work)
      return false;
    work += count;
    return true;
  };
  for (Operation &op : module.getBody()->getOperations()) {
    if (!charge())
      return module.emitError("domain composition exceeds 1048576 work units");
    FlatSymbolRefAttr primary;
    StringRef name;
    if (auto domain = dyn_cast<upf::UPFDomainOp>(op)) {
      primary = domain.getPrimaryAttr();
      name = domain.getSymName();
    } else if (auto domain = dyn_cast<upf::UPFCompositeDomainOp>(op)) {
      primary = domain.getPrimaryAttr();
      name = domain.getSymName();
    } else
      continue;
    if (!indices.try_emplace(name, nodes.size()).second)
      return op.emitError("duplicate domain identity");
    nodes.push_back({&op, primary, {}, 0});
  }
  for (auto &node : nodes) {
    auto composite = dyn_cast<upf::UPFCompositeDomainOp>(node.domain);
    if (!composite)
      continue;
    for (auto reference : composite.getSubdomains()) {
      if (!charge(7))
        return composite.emitError(
            "domain composition exceeds 1048576 work units");
      auto found = indices.find(cast<FlatSymbolRefAttr>(reference).getValue());
      if (found == indices.end())
        return composite.emitError("references an unknown composite subdomain");
      auto &child = nodes[found->second];
      if (!child.primary)
        return composite.emitError(
            "subdomain requires a resolved primary supply set");
      if (!relations.matches(node.primary, child.primary,
                             upf::SupplyEquivalenceKind::Interchangeable,
                             false))
        return composite.emitError(
            "composite and subdomain primaries must be electrically equivalent "
            "or functionally equivalent and interchangeable");
      node.children.push_back(found->second);
      ++child.incoming;
    }
  }
  std::queue<unsigned> ready;
  for (auto [index, node] : llvm::enumerate(nodes))
    if (!node.incoming)
      ready.push(index);
  size_t visited = 0;
  while (!ready.empty()) {
    unsigned index = ready.front();
    ready.pop();
    ++visited;
    for (unsigned child : nodes[index].children)
      if (!--nodes[child].incoming)
        ready.push(child);
  }
  if (visited != nodes.size())
    for (auto &node : nodes)
      if (node.incoming && isa<upf::UPFCompositeDomainOp>(node.domain))
        return node.domain->emitError("cycle in composite domain composition");
  return success();
}
LogicalResult validateUPFCompositeDomains(ModuleOp module) {
  if (module.getOps<upf::UPFCompositeDomainOp>().empty())
    return success();
  SupplyRelations relations(module);
  if (failed(relations.initialize()))
    return failure();
  return validateUPFCompositeDomains(module, relations);
}
} // namespace talos
