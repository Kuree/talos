//===- PrepareSAIFLibrary.cpp - Resolve library forward SAIF by cell type -===//
#include "PrepareSAIFLibrary.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/StringMap.h"
using namespace mlir;
namespace talos {
FailureOr<ArrayAttr>
prepareSAIFLibrary(ModuleOp module, ArrayRef<saif::FileOp> files,
                   const llvm::DenseMap<uint64_t, saif::PathAttr> &scopePaths,
                   ArrayRef<Attribute> bindings, ArrayRef<uint8_t> outputs) {
  auto *context = module.getContext();
  llvm::StringMap<saif::CellOp> declarations;
  bool invalid = false;
  for (auto file : files)
    file.walk([&](saif::CellOp cell) {
      auto name = cast<saif::IdentifierAttr>(cell.getName().getComponents()[0]);
      if (!declarations.try_emplace(name.getName().getValue(), cell).second) {
        cell.emitError("duplicate library SAIF cell characterization");
        invalid = true;
      }
    });
  if (declarations.empty())
    return ArrayAttr::get(context, {});
  llvm::DenseMap<Operation *, llvm::DenseSet<saif::IdentifierAttr>>
      relatedInputs;
  for (auto &entry : declarations)
    entry.second.walk([&](saif::PathOp path) {
      for (Attribute pin : path.getPins())
        relatedInputs[entry.second].insert(cast<saif::IdentifierAttr>(pin));
    });
  llvm::MapVector<saif::PathAttr, StringAttr> instances;
  module.walk([&](sim::SimScopeDeclOp scope) {
    if (auto definition = scope.getDefinitionNameAttr())
      if (declarations.count(definition.getValue()))
        if (auto found = scopePaths.find(scope.getId());
            found != scopePaths.end())
          instances[found->second] = definition;
  });
  for (Attribute attr : bindings) {
    auto binding = cast<saif::BindingAttr>(attr);
    if (auto type = binding.getVirtualType())
      if (declarations.count(type.getValue()))
        instances[binding.getInstance()] = type;
  }
  llvm::DenseMap<saif::PathAttr, SmallVector<saif::PinBindingAttr>>
      pinsByInstance;
  for (auto [index, attr] : llvm::enumerate(bindings)) {
    auto binding = cast<saif::BindingAttr>(attr);
    if (!binding.getPort() || !instances.count(binding.getInstance()))
      continue;
    bool output = outputs[index] != 0;
    if (auto type = binding.getVirtualType()) {
      auto declaration = declarations.lookup(type.getValue());
      if (relatedInputs[declaration].contains(binding.getSignal()))
        output = false;
    }
    pinsByInstance[binding.getInstance()].push_back(
        saif::PinBindingAttr::get(context, binding.getSignal(), index, output));
  }
  SmallVector<Attribute> cells;
  auto paths = [&](saif::PathsOp source) {
    SmallVector<Attribute> result;
    for (auto related : source.getBody().front().getOps<saif::PathOp>())
      result.push_back(saif::RelatedAttr::get(context, related.getPins(),
                                              related.getIsDefault()));
    return ArrayAttr::get(context, result);
  };
  for (const auto &entry : instances) {
    auto declaration = declarations.lookup(entry.second.getValue());
    auto &pinList = pinsByInstance[entry.first];
    llvm::DenseMap<saif::IdentifierAttr, uint64_t> pinIndices;
    for (auto pin : pinList)
      pinIndices[pin.getName()] = pin.getObservation();
    SmallVector<Attribute> groups;
    auto group = [&](Operation *container, uint64_t observation, bool leakage) {
      for (Operation &directive : container->getRegion(0).front()) {
        SmallVector<Attribute> rules;
        bool conditional = isa<saif::ConditionsOp>(directive);
        if (auto conditions = dyn_cast<saif::ConditionsOp>(directive)) {
          for (auto when :
               conditions.getBody().front().getOps<saif::WhenOp>()) {
            ArrayAttr related = ArrayAttr::get(context, {});
            for (auto items : when.getBody().front().getOps<saif::PathsOp>())
              related = paths(items);
            rules.push_back(saif::RuleAttr::get(
                context, when.getConditionAttr(),
                when.getEdge() == saif::Edge::RiseFall, related));
          }
        } else if (auto items = dyn_cast<saif::PathsOp>(directive)) {
          rules.push_back(saif::RuleAttr::get(context, saif::ConditionAttr{},
                                              false, paths(items)));
        }
        if (!rules.empty())
          groups.push_back(
              saif::GroupAttr::get(context, observation, leakage, conditional,
                                   ArrayAttr::get(context, rules)));
      }
    };
    for (auto port :
         declaration.getBody().front().getOps<saif::PortDirectiveOp>()) {
      auto pin = cast<saif::IdentifierAttr>(port.getName().getComponents()[0]);
      auto found = pinIndices.find(pin);
      if (found == pinIndices.end()) {
        port.emitError("library SAIF pin does not resolve in an elaborated "
                       "cell instance: ")
            << entry.first;
        invalid = true;
      } else
        group(port, found->second, false);
    }
    for (auto leakage : declaration.getBody().front().getOps<saif::LeakageOp>())
      group(leakage, UINT64_MAX, true);
    SmallVector<Attribute> pins(pinList.begin(), pinList.end());
    cells.push_back(saif::CellBindingAttr::get(
        context, entry.first, entry.second, ArrayAttr::get(context, pins),
        ArrayAttr::get(context, groups)));
  }
  return invalid ? FailureOr<ArrayAttr>(failure())
                 : ArrayAttr::get(context, cells);
}
} // namespace talos
