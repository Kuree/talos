#include "SupplyRelations.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/Pass/Pass.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include <map>
#include <set>

using namespace mlir;
namespace talos {
LogicalResult normalizeUPFSupplyEquivalences(ModuleOp module) {
  bool hasEquivalences = !module.getOps<upf::UPFSupplyEquivalenceOp>().empty();
  if (!hasEquivalences && module.getOps<upf::UPFCompositeDomainOp>().empty())
    return success();
  bool encoded = native::has<native::PartitionManifests>(module) ||
                 native::has<native::PhysicalPartitionManifest>(module) ||
                 runtime::has<runtime::BytecodeImage>(module) ||
                 runtime::has<runtime::LLVMPrepared>(module) ||
                 runtime::has<runtime::Materialized>(module);
  for (auto design : module.getOps<sim::SimDesignOp>()) {
    encoded |= bool(design.getComputeGraphAttr()) ||
               native::has<native::PartitionManifest>(design);
    for (auto function : design.getOps<sim::SimFuncOp>())
      encoded |= runtime::has<runtime::BytecodeFunction>(function) ||
                 native::has<native::Frame>(function);
  }
  if (encoded)
    return module.emitError(
        "supply equivalence must be resolved before scheduling and encoding");
  SupplyRelations relations(module);
  if (failed(relations.initialize()))
    return failure();
  if (failed(validateUPFCompositeDomains(module, relations)))
    return failure();
  if (!hasEquivalences)
    return success();
  auto roots = relations.supplies();
  llvm::StringMap<unsigned> indices;
  for (auto [index, supply] : llvm::enumerate(roots)) {
    auto declaration = supply;
    indices[declaration.getSymName()] = index;
  }
  auto leader = [&](FlatSymbolRefAttr reference) {
    return relations.electricalLeader(
        indices.find(reference.getValue())->second);
  };
  std::set<unsigned> computed;
  for (auto domain : module.getOps<upf::UPFDomainOp>()) {
    if (!domain.getInputAttr() || domain.getAnonymousParentAttr())
      continue;
    if (leader(domain.getInputAttr()) == leader(domain.getPowerAttr()))
      return domain.emitError("power-switch input and output cannot be "
                              "declared electrically equivalent");
    if (!computed.insert(leader(domain.getPowerAttr())).second)
      return domain.emitError(
          "electrical equivalence of distinct computed switch outputs requires "
          "a resolved network and is not implemented");
  }
  for (auto declaration : module.getOps<upf::UPFSupplyEquivalenceOp>()) {
    if (declaration.getKind() == upf::SupplyEquivalenceKind::Electrical)
      continue;
    bool needsProof = false;
    auto first = cast<FlatSymbolRefAttr>(declaration.getObjects()[0]);
    for (auto value : declaration.getObjects().getValue().drop_front()) {
      auto ref = cast<FlatSymbolRefAttr>(value);
      if (auto left =
              module.lookupSymbol<upf::UPFSupplySetOp>(first.getValue())) {
        auto right = module.lookupSymbol<upf::UPFSupplySetOp>(ref.getValue());
        for (auto function : left.getPopulatedFunctions()) {
          if (!llvm::is_contained(right.getPopulatedFunctions(), function))
            continue;
          auto name = cast<StringAttr>(function).getValue();
          unsigned a =
              leader(left.getFunctions().getAs<FlatSymbolRefAttr>(name));
          unsigned b =
              leader(right.getFunctions().getAs<FlatSymbolRefAttr>(name));
          needsProof |= a != b && (computed.count(a) || computed.count(b));
        }
      } else {
        unsigned a = leader(first), b = leader(ref);
        needsProof |= a != b && (computed.count(a) || computed.count(b));
      }
    }
    if (needsProof)
      return declaration.emitError(
          "functional equivalence involving computed supplies requires "
          "switch-behavior proofs and is not implemented");
  }
  std::map<unsigned, SmallVector<upf::UPFSupplyOp>> groups;
  for (auto [index, supply] : llvm::enumerate(roots))
    groups[relations.electricalLeader(index)].push_back(supply);
  struct Merge {
    upf::UPFSupplyOp target;
    ArrayAttr names;
    bool writable, alwaysOn;
  };
  SmallVector<Merge> merges;
  llvm::DenseMap<Operation *, FlatSymbolRefAttr> replacements;
  for (auto &[leader, members] : groups) {
    if (members.size() == 1)
      continue;
    if (computed.count(leader))
      return members.front().emitError(
          "electrical equivalence with a computed root requires physical "
          "source provenance and is not implemented");
    auto target = members.front();
    bool writable = true, alwaysOn = false;
    std::set<StringRef> names;
    for (auto supply : members) {
      if (upf::conflictingInitialSupplyValues(supply.getInitialValue(),
                                              target.getInitialValue()))
        return supply.emitError("declared electrical equivalence contradicts "
                                "initial supply values");
      writable &= supply.getWritable();
      alwaysOn |= supply.getAlwaysOn();
      for (auto value : supply.getNames())
        names.insert(cast<StringAttr>(value).getValue());
      if (supply != target)
        replacements[supply] =
            FlatSymbolRefAttr::get(module.getContext(), target.getSymName());
    }
    SmallVector<Attribute> attributes;
    for (StringRef name : names)
      attributes.push_back(StringAttr::get(module.getContext(), name));
    merges.push_back({target, ArrayAttr::get(module.getContext(), attributes),
                      writable, alwaysOn});
  }
  if (merges.empty())
    return success();
  // Rewriting typed references must preserve lexical symbol lookup. An inner
  // symbol named like a supply is not that supply. Plan all edits before
  // changing declarations, including nested attribute references.
  SymbolTableCollection symbols;
  SmallVector<std::pair<Operation *, DictionaryAttr>> edits;
  size_t work = 0;
  bool invalid = false;
  module.walk([&](Operation *op) {
    if (invalid)
      return;
    if (++work > 1048576) {
      op->emitError(
          "electrical supply normalization exceeds 1048576 work units");
      invalid = true;
      return;
    }
    AttrTypeReplacer replacer;
    replacer.addReplacement(
        [&](SymbolRefAttr reference) -> std::optional<Attribute> {
          if (invalid)
            return std::nullopt;
          if (++work > 1048576) {
            op->emitError(
                "electrical supply normalization exceeds 1048576 work units");
            invalid = true;
            return std::nullopt;
          }
          Operation *root =
              symbols.lookupNearestSymbolFrom(op, reference.getRootReference());
          if (!reference.getNestedReferences().empty() &&
              replacements.count(root)) {
            op->emitError("nested reference rooted at a merged supply cannot "
                          "be canonicalized");
            invalid = true;
            return std::nullopt;
          }
          Operation *target = symbols.lookupNearestSymbolFrom(op, reference);
          auto found = replacements.find(target);
          if (found == replacements.end())
            return std::nullopt;
          return found->second;
        });
    auto previous = op->getAttrDictionary();
    if (auto set = dyn_cast<upf::UPFSupplySetOp>(op)) {
      if (auto states = set.getStatesAttr()) {
        SmallVector<Attribute> resolvedStates;
        bool changed = false;
        for (auto value : states) {
          if (++work > 1048576) {
            set.emitError(
                "electrical supply normalization exceeds 1048576 work units");
            invalid = true;
            return;
          }
          auto state = cast<upf::PowerStateAttr>(value);
          auto condition = state.getCondition();
          if (condition) {
            SmallVector<Attribute> tokens;
            for (auto value : condition.getTokens()) {
              size_t cost = 1 + set.getRequired().size();
              if (cost > 1048576 - work) {
                set.emitError("electrical supply normalization exceeds 1048576 "
                              "work units");
                invalid = true;
                return;
              }
              work += cost;
              auto token = cast<upf::SupplyExpressionTokenAttr>(value);
              if (token.getSupply() && !token.getFunction() &&
                  !token.getOriginFunctions()) {
                SmallVector<Attribute> roles;
                for (auto function : set.getRequired())
                  if (set.getFunctions().get(
                          cast<StringAttr>(function).getValue()) ==
                      token.getSupply())
                    roles.push_back(function);
                token = upf::SupplyExpressionTokenAttr::get(
                    module.getContext(), token.getOpcode(), token.getSupply(),
                    StringAttr{}, token.getValue(), token.getReal(),
                    ArrayAttr::get(module.getContext(), roles));
                changed = true;
              }
              tokens.push_back(token);
            }
            condition = upf::SupplyExpressionAttr::get(
                module.getContext(),
                ArrayAttr::get(module.getContext(), tokens));
          }
          resolvedStates.push_back(upf::PowerStateAttr::get(
              module.getContext(), state.getName(), condition,
              state.getSimstate(), state.getIllegal()));
        }
        if (changed) {
          NamedAttrList attributes(previous);
          attributes.set("states",
                         ArrayAttr::get(module.getContext(), resolvedStates));
          previous = attributes.getDictionary(module.getContext());
        }
      }
    }
    auto next = cast<DictionaryAttr>(replacer.replace(previous));
    if (next != op->getAttrDictionary())
      edits.push_back({op, next});
  });
  if (invalid)
    return failure();
  for (auto &edit : edits)
    edit.first->setAttrs(edit.second);
  for (auto &merge : merges) {
    merge.target.setNamesAttr(merge.names);
    merge.target.setWritable(merge.writable && !merge.alwaysOn);
    merge.target.setAlwaysOn(merge.alwaysOn);
  }
  for (auto &entry : replacements)
    entry.first->erase();
  return success();
}
namespace {
struct NormalizeEquivalencesPass
    : PassWrapper<NormalizeEquivalencesPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NormalizeEquivalencesPass)
  StringRef getArgument() const final { return "normalize-upf-equivalences"; }
  StringRef getDescription() const final {
    return "Validate supply relations and canonicalize declared electrical "
           "rails";
  }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<upf::UPFDialect>();
  }
  void runOnOperation() override {
    if (failed(normalizeUPFSupplyEquivalences(getOperation())))
      signalPassFailure();
  }
};
} // namespace
std::unique_ptr<Pass> createNormalizeUPFSupplyEquivalencesPass() {
  return std::make_unique<NormalizeEquivalencesPass>();
}
} // namespace talos
