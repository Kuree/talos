#include "SupplyRelations.h"
#include "llvm/ADT/STLExtras.h"
#include <map>
#include <set>

using namespace mlir;
namespace talos {
bool SupplyRelations::charge(size_t count) {
  if (count > 1048576 - work)
    return false;
  work += count;
  return true;
}
unsigned SupplyRelations::root(Attribute reference) const {
  return indices.find(cast<FlatSymbolRefAttr>(reference).getValue())->second;
}
const llvm::IntEqClasses &SupplyRelations::classes(Kind kind) const {
  return kind == Kind::Electrical        ? electrical
         : kind == Kind::Interchangeable ? interchangeable
                                         : functional;
}
bool SupplyRelations::matches(FlatSymbolRefAttr a, FlatSymbolRefAttr b,
                              Kind kind, bool pgOnly) const {
  if (!a || !b)
    return false;
  auto left = sets.lookup(a.getValue()), right = sets.lookup(b.getValue());
  if (!left || !right)
    return false;
  if (!pgOnly && (left.getRequired().size() != right.getRequired().size() ||
                  !llvm::all_of(left.getRequired(), [&](Attribute function) {
                    return llvm::is_contained(right.getRequired(), function);
                  })))
    return false;
  if (pgOnly)
    for (StringRef name : {"power", "ground"})
      if (!llvm::is_contained(left.getPopulatedFunctions(),
                              StringAttr::get(module->getContext(), name)) ||
          !llvm::is_contained(right.getPopulatedFunctions(),
                              StringAttr::get(module->getContext(), name)))
        return false;
  const auto &relation = classes(kind);
  const auto &setRelation = kind == Kind::Electrical        ? setElectrical
                            : kind == Kind::Interchangeable ? setInterchangeable
                                                            : setFunctional;
  if (setRelation.findLeader(setIndices.lookup(a.getValue())) ==
      setRelation.findLeader(setIndices.lookup(b.getValue())))
    return true;
  // Dormant requirements describe no use yet, not universal equivalence.
  bool dormant = !pgOnly && left.getRequired().empty();
  if (dormant && (left.getPopulatedFunctions().size() != 6 ||
                  right.getPopulatedFunctions().size() != 6))
    return false;
  for (StringRef function : upf::getSupplyFunctionNames()) {
    if (pgOnly
            ? function != "power" && function != "ground"
            : !dormant && !llvm::is_contained(
                              left.getRequired(),
                              StringAttr::get(module->getContext(), function)))
      continue;
    if (relation.findLeader(root(left.getFunctions().get(function))) !=
        relation.findLeader(root(right.getFunctions().get(function))))
      return false;
  }
  return true;
}
LogicalResult SupplyRelations::initialize(InitialValues initialValues) {
  for (auto supply : module.getOps<upf::UPFSupplyOp>()) {
    if (!charge() ||
        !indices.try_emplace(supply.getSymName(), roots.size()).second)
      return supply.emitError(
          "duplicate supply identity or supply relation work limit exceeded");
    roots.push_back(supply);
  }
  electrical.grow(roots.size());
  interchangeable.grow(roots.size());
  functional.grow(roots.size());
  for (auto set : module.getOps<upf::UPFSupplySetOp>()) {
    if (!charge(7) || !sets.try_emplace(set.getSymName(), set).second)
      return set.emitError(
          "duplicate supply set or supply relation work limit exceeded");
    for (StringRef function : upf::getSupplyFunctionNames()) {
      auto ref = set.getFunctions().getAs<FlatSymbolRefAttr>(function);
      if (!ref || !indices.count(ref.getValue()))
        return set.emitError(
            "supply relation requires six known function roots");
    }
  }
  for (const auto &entry : sets)
    setIndices[entry.getKey()] = setIndices.size();
  setElectrical.grow(sets.size());
  setInterchangeable.grow(sets.size());
  setFunctional.grow(sets.size());
  for (const auto &entry : sets) {
    auto set = entry.second;
    if (auto associated = set.getAssociatedAttr())
      for (auto value : associated) {
        if (!charge())
          return set.emitError("supply relation exceeds 1048576 work units");
        auto other = setIndices.find(cast<FlatSymbolRefAttr>(value).getValue());
        if (other == setIndices.end())
          return set.emitError(
              "supply relation references an unknown associated set");
        unsigned id = setIndices.lookup(set.getSymName());
        setElectrical.join(id, other->second);
        setInterchangeable.join(id, other->second);
        setFunctional.join(id, other->second);
      }
  }
  SymbolTableCollection symbols;
  auto declarations = module.getOps<upf::UPFSupplyEquivalenceOp>();
  for (auto declaration : declarations) {
    if (!charge(declaration.getObjects().size() * 7) ||
        failed(declaration.verify()) ||
        failed(declaration.verifySymbolUses(symbols)))
      return declaration.emitError(
          "invalid supply equivalence or 1048576-unit relation limit exceeded");
    auto first = cast<FlatSymbolRefAttr>(declaration.getObjects()[0]);
    bool fullSet = sets.count(first.getValue());
    auto join = [&](unsigned a, unsigned b) {
      functional.join(a, b);
      if (declaration.getKind() != Kind::Functional)
        interchangeable.join(a, b);
      if (declaration.getKind() == Kind::Electrical)
        electrical.join(a, b);
    };
    for (auto value : declaration.getObjects().getValue().drop_front()) {
      if (!fullSet)
        join(root(first), root(value));
      else {
        auto left = sets.lookup(first.getValue());
        auto right = sets.lookup(cast<FlatSymbolRefAttr>(value).getValue());
        unsigned a = setIndices.lookup(left.getSymName());
        unsigned b = setIndices.lookup(right.getSymName());
        setFunctional.join(a, b);
        if (declaration.getKind() != Kind::Functional)
          setInterchangeable.join(a, b);
        if (declaration.getKind() == Kind::Electrical)
          setElectrical.join(a, b);
      }
    }
  }
  // A populated role may be connected through unpopulated intermediary sets.
  // Project complete equivalence classes, not just each declaration's direct
  // pairs; never attach an intermediary's placeholder value to that role.
  auto project = [&](const llvm::IntEqClasses &setClasses, Kind kind) {
    std::map<std::pair<unsigned, unsigned>, unsigned> representatives;
    for (const auto &entry : sets) {
      auto set = entry.second;
      unsigned group =
          setClasses.findLeader(setIndices.lookup(set.getSymName()));
      for (auto [index, function] :
           llvm::enumerate(upf::getSupplyFunctionNames())) {
        if (!charge())
          return false;
        if (!llvm::is_contained(set.getPopulatedFunctions(),
                                StringAttr::get(module.getContext(), function)))
          continue;
        unsigned value = root(set.getFunctions().get(function));
        auto [previous, inserted] =
            representatives.emplace(std::pair{group, unsigned(index)}, value);
        if (inserted)
          continue;
        functional.join(previous->second, value);
        if (kind != Kind::Functional)
          interchangeable.join(previous->second, value);
        if (kind == Kind::Electrical)
          electrical.join(previous->second, value);
      }
    }
    return true;
  };
  if (!project(setElectrical, Kind::Electrical) ||
      !project(setInterchangeable, Kind::Interchangeable) ||
      !project(setFunctional, Kind::Functional))
    return module.emitError(
        "supply relation projection exceeds 1048576 work units");
  if (initialValues == InitialValues::Check) {
    std::map<unsigned, uint64_t> constants;
    for (auto supply : roots) {
      unsigned group =
          functional.findLeader(indices.lookup(supply.getSymName()));
      auto [entry, inserted] =
          constants.emplace(group, supply.getInitialValue());
      if (!inserted && upf::conflictingInitialSupplyValues(
                           entry->second, supply.getInitialValue()))
        return supply.emitError(
            "functional equivalence contradicts known initial supply values");
    }
  }
  for (auto declaration : declarations) {
    if (declaration.getKind() != Kind::Functional)
      continue;
    // Prohibitions retain their original group granularity and do not become
    // a transitive relation. Check both explicit whole-set evidence and stable
    // function identities; an empty required mask alone proves nothing.
    std::set<SmallVector<unsigned>> fingerprints;
    std::set<unsigned> explicitSets;
    for (auto value : declaration.getObjects()) {
      if (!charge(7))
        return declaration.emitError(
            "supply relation exceeds 1048576 work units");
      SmallVector<unsigned> fingerprint;
      auto set = sets.lookup(cast<FlatSymbolRefAttr>(value).getValue());
      if (!set)
        fingerprint.push_back(interchangeable.findLeader(root(value)));
      else {
        unsigned group =
            setInterchangeable.findLeader(setIndices.lookup(set.getSymName()));
        if (!explicitSets.insert(group).second)
          return declaration.emitError("non-interchangeability contradicts an "
                                       "explicit interchangeable set relation");
        if (set.getRequired().empty() &&
            set.getPopulatedFunctions().size() != 6)
          continue;
        for (StringRef function : upf::getSupplyFunctionNames())
          if (set.getRequired().empty() ||
              llvm::is_contained(
                  set.getRequired(),
                  StringAttr::get(module.getContext(), function)))
            fingerprint.push_back(interchangeable.findLeader(
                root(set.getFunctions().get(function))));
      }
      if (!fingerprints.insert(std::move(fingerprint)).second)
        return declaration.emitError(
            "non-interchangeability contradicts electrical or interchangeable "
            "supply equivalence");
    }
  }
  return success();
}
} // namespace talos
