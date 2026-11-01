//===- PruneVPIInventory.cpp - Drop VPI inventory nothing can read --------===//
//
// Elaboration records the VPI object model in declarations of the design: in a
// large design, most of its operations. Only the serialized design database
// reads them, and it exists only for a VPI profile or a waveform dump. Without
// either, every whole-design scan would still walk through them.
//
//===----------------------------------------------------------------------===//

#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/Transforms/Passes.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_TALOSSIMPRUNEVPIINVENTORYPASS
#include "talos/Dialect/Simulation/Transforms/Passes.h.inc"

namespace {

/// Inventory that no other operation names.
bool isInventoryRecord(Operation *op) {
  return isa<sim::SimVPIRelationDeclOp, sim::SimVPIStatementRelationDeclOp,
             sim::SimVPIDefinitionTypeDefaultOp,
             sim::SimVPIDefinitionMemberSpecializationOp,
             sim::SimVPIDefinitionMemberInstanceBindingOp,
             sim::SimVPIDefinitionMemberInstanceRelationOp,
             sim::SimVPINetIdentityDeclOp>(op);
}

/// Inventory that exists only to be named by records and by each other.
bool isInventorySymbol(Operation *op) {
  return isa<sim::SimVPIExpressionDeclOp, sim::SimVPIDefinitionMemberDeclOp>(
      op);
}

class TalosSimPruneVPIInventoryPass final
    : public impl::TalosSimPruneVPIInventoryPassBase<
          TalosSimPruneVPIInventoryPass> {
public:
  void runOnOperation() override {
    sim::SimDesignOp design = getOperation();
    if (design.getBody().empty() ||
        analysis::anyNested<Operation *>(design, [](Operation *op) {
          return isa<sim::SimDumpOpenOp, sim::SimDumpOpenStringOp,
                     sim::SimDumpTimescaleOp, sim::SimDumpVarsOp,
                     sim::SimDumpAllOp, sim::SimDumpControlOp,
                     sim::SimDumpLimitOp, sim::SimDumpFlushOp,
                     sim::SimDumpPortsOp, sim::SimDumpPortsControlOp>(op);
        }))
      return markAllAnalysesPreserved();
    auto uses = analysis::getSymbolUsesConcurrently(&design.getBody());
    if (!uses)
      return markAllAnalysesPreserved();

    // A symbol stays if anything but a record names it, directly or through
    // another symbol that stays.
    DenseMap<StringAttr, Operation *> symbols;
    SmallVector<Operation *> records;
    for (Operation &op : design.getBody().front()) {
      if (isInventoryRecord(&op))
        records.push_back(&op);
      else if (isInventorySymbol(&op))
        symbols[SymbolTable::getSymbolName(&op)] = &op;
    }
    DenseMap<Operation *, SmallVector<StringAttr, 2>> named;
    SmallVector<Operation *> live;
    DenseSet<Operation *> kept;
    auto keep = [&](StringAttr name) {
      if (Operation *symbol = symbols.lookup(name))
        if (kept.insert(symbol).second)
          live.push_back(symbol);
    };
    for (const SymbolTable::SymbolUse &use : *uses) {
      Operation *user = use.getUser();
      StringAttr name = use.getSymbolRef().getRootReference();
      if (isInventoryRecord(user))
        continue;
      if (isInventorySymbol(user))
        named[user].push_back(name);
      else
        keep(name);
    }
    while (!live.empty())
      for (StringAttr name : named.lookup(live.pop_back_val()))
        keep(name);

    sim::set<sim::metadata::VpiInventoryPruned>(
        design, UnitAttr::get(design.getContext()));
    for (Operation *record : records)
      record->erase();
    for (const auto &[name, symbol] : symbols)
      if (!kept.contains(symbol))
        symbol->erase();
  }
};

} // namespace
} // namespace talos
