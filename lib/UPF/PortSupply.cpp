#include "PortSupply.h"
#include "mlir/IR/BuiltinOps.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/STLExtras.h"
#include <set>

using namespace mlir;
namespace talos {
PortSupplyAnalysis::PortSupplyAnalysis(ModuleOp module, sim::SimDesignOp design)
    : module(module), design(design) {}
bool PortSupplyAnalysis::charge(size_t count) {
  if (count > 1048576 - work)
    return false;
  work += count;
  return true;
}
bool PortSupplyAnalysis::Domain::contains(StringRef path) const {
  size_t yes = 0, no = 0;
  for (auto entry : included) {
    auto root = cast<StringAttr>(entry).getValue();
    if (upf::isWithinPath(path, root))
      yes = std::max(yes, root.size());
  }
  if (excluded)
    for (auto entry : excluded) {
      auto root = cast<StringAttr>(entry).getValue();
      if (upf::isWithinPath(path, root))
        no = std::max(no, root.size());
    }
  return yes > no;
}
FailureOr<const PortSupplyAnalysis::Domain *>
PortSupplyAnalysis::domain(StringRef path) {
  const Domain *result = nullptr;
  for (const auto &candidate : domains) {
    if (!charge(candidate.included.size() +
                (candidate.excluded ? candidate.excluded.size() : 0))) {
      module.emitError("port supply analysis exceeds 1048576 work units");
      return failure();
    }
    if (candidate.contains(path)) {
      if (result) {
        module.emitError("port has ambiguous physical domain ownership");
        return failure();
      }
      result = &candidate;
    }
  }
  return result;
}
StringRef PortSupplyAnalysis::owner(sim::SimPortDeclOp port) const {
  auto found = scopes.find(port.getScopeId());
  if (found == scopes.end())
    return {};
  auto declaration = found->second;
  return declaration.getHierarchicalName().value_or(StringRef{});
}
bool PortSupplyAnalysis::equal(FlatSymbolRefAttr a, FlatSymbolRefAttr b,
                               bool pgOnly,
                               upf::SupplyEquivalenceKind kind) const {
  if (relations)
    return relations->matches(a, b, kind, pgOnly);
  if (!a || !b)
    return false;
  if (a == b)
    return true;
  auto left = sets.lookup(a.getValue()), right = sets.lookup(b.getValue());
  if (!left || !right)
    return false;
  if (!pgOnly && (left.getRequired().size() != right.getRequired().size() ||
                  !llvm::all_of(left.getRequired(), [&](Attribute function) {
                    return llvm::is_contained(right.getRequired(), function);
                  })))
    return false;
  for (StringRef function : upf::getSupplyFunctionNames()) {
    if (pgOnly && function != "power" && function != "ground")
      continue;
    if (left.getFunctions().get(function) != right.getFunctions().get(function))
      return false;
  }
  return true;
}
LogicalResult PortSupplyAnalysis::initialize() {
  if (!design)
    return success();
  auto ports = module.getOps<upf::UPFPortAttributesOp>();
  bool hasValues = false;
  design.walk([&](upf::UPFPortValueOp) { hasValues = true; });
  if (ports.empty() && design.getOps<upf::UPFPortBindingOp>().empty() &&
      !hasValues)
    return success();
  relations.emplace(module);
  if (failed(relations->initialize()))
    return failure();
  for (auto scope : design.getOps<sim::SimScopeDeclOp>()) {
    if (!charge())
      return scope.emitError(
          "port supply inventory exceeds 1048576 work units");
    if (!scopes.try_emplace(scope.getId(), scope).second)
      return scope.emitError("duplicate port inventory scope");
    if (auto path = scope.getHierarchicalName())
      semanticScopes[*path] =
          bool(scope.getDefinitionName() || scope.getInterfaceType() ||
               !scope.getParent());
  }
  for (auto hierarchy : module.getOps<upf::UPFHierarchyOp>())
    for (auto entry : hierarchy.getScopes()) {
      if (!charge())
        return hierarchy.emitError(
            "port supply inventory exceeds 1048576 work units");
      auto scope = cast<upf::HierarchyScopeAttr>(entry);
      semanticScopes[scope.getPath().getValue()] = scope.getInstance();
    }
  std::map<std::pair<uint64_t, uint64_t>, sim::SimPortDeclOp> formals;
  for (auto port : design.getOps<sim::SimPortDeclOp>()) {
    if (!charge())
      return port.emitError("port supply inventory exceeds 1048576 work units");
    if (!formals.emplace(std::pair{port.getScopeId(), port.getOrdinal()}, port)
             .second ||
        !paths.try_emplace(port.getHierarchicalName(), port).second)
      return port.emitError("port supply inventory requires unique formal and "
                            "logical port identities");
    if (owner(port).empty())
      return port.emitError("port has no declared owning instance scope");
    // Simulation reflection joins its scope and raw formal name. Slang's HDL
    // paths print an escaped identifier (including a terminating space) for
    // names such as p[0]. Bridge those spellings using the actual declaration,
    // never by treating a bit-select string as another port's storage alias.
    if (auto name = port.getDebugName(); name && !name->empty()) {
      if ((owner(port) + "." + *name).str() == port.getHierarchicalName()) {
        auto escaped = (owner(port) + ".\\" + *name + " ").str();
        auto [entry, inserted] = paths.try_emplace(escaped, port);
        if (!inserted && entry->second != port)
          return port.emitError("ambiguous escaped logical port identity");
      }
    }
  }
  for (auto storage : design.getOps<sim::SimStorageDeclOp>()) {
    if (!charge())
      return storage.emitError(
          "port supply inventory exceeds 1048576 work units");
    roots.emplace(std::pair{false, storage.getId()},
                  Root{storage.getScopeId(),
                       sim::getPackedWidth(storage.getType()).value_or(0)});
  }
  for (auto net : design.getOps<sim::SimNetDeclOp>()) {
    if (!charge())
      return net.emitError("port supply inventory exceeds 1048576 work units");
    roots.emplace(
        std::pair{true, net.getId()},
        Root{net.getScopeId(), sim::getPackedWidth(net.getType()).value_or(0)});
  }
  llvm::DenseMap<uint64_t, sim::SimCodeUnitDeclOp> units;
  for (auto unit : design.getOps<sim::SimCodeUnitDeclOp>()) {
    if (!charge())
      return unit.emitError("port supply inventory exceeds 1048576 work units");
    units.try_emplace(unit.getId(), unit);
  }
  std::set<std::pair<uint64_t, uint64_t>> bound;
  std::set<uint64_t> boundActors;
  for (auto binding : design.getOps<upf::UPFPortBindingOp>()) {
    if (!charge())
      return binding.emitError("port binding checks exceed 1048576 work units");
    auto formal = std::pair{binding.getScope(), binding.getOrdinal()};
    auto port = formals.find(formal);
    auto unit = units.lookup(binding.getActor());
    if ((!binding.getOpaque() && port == formals.end()) || !unit)
      return binding.emitError(
          "port binding references an unknown formal or code unit");
    if (!bound.insert(formal).second ||
        !boundActors.insert(binding.getActor()).second)
      return binding.emitError("duplicate formal or actor in port bindings");
    auto scope = scopes.lookup(binding.getScope());
    if (!scope || !scope.getParent() || unit.getScopeId() != *scope.getParent())
      return binding.emitError(
          "port connection actor must belong to the formal's parent scope");
    auto kind = unit.getCodeUnitKind();
    if (kind != sim::EntryKind::PortOutput &&
        kind != sim::EntryKind::PortInput &&
        kind != sim::EntryKind::PortInitialize)
      return binding.emitError("port binding requires a port connection actor");
    if (binding.getOpaque()) {
      if (port != formals.end())
        return binding.emitError(
            "opaque port binding has a reflected declaration");
      hasOpaque = true;
      if (kind == sim::EntryKind::PortOutput)
        opaqueOutputs.push_back(binding.getScope());
      continue;
    }
    actors.try_emplace(binding.getActor(), port->second);
    formalActors.try_emplace(port->second.getId(), binding.getActor());
    if (port->second.getDirection() == sim::PortDirection::Output
            ? kind != sim::EntryKind::PortOutput
            : (kind != sim::EntryKind::PortInput &&
               kind != sim::EntryKind::PortInitialize))
      return binding.emitError(
          "port connection actor kind disagrees with formal direction");
  }
  bool invalidValue = false;
  std::set<uint64_t> markedActors;
  design.walk([&](upf::UPFPortValueOp value) {
    auto fn = value->getParentOfType<sim::SimFuncOp>();
    if (!charge() || !fn || !fn.getCodeUnitId() ||
        *fn.getCodeUnitId() != value.getActor() ||
        fn.getEntryKind() != sim::EntryKind::PortOutput ||
        !boundActors.count(value.getActor()) ||
        !markedActors.insert(value.getActor()).second) {
      value.emitError("port value requires one immutable output actor binding "
                      "and matching code-unit identity");
      invalidValue = true;
    }
  });
  if (invalidValue)
    return failure();
  for (auto set : module.getOps<upf::UPFSupplySetOp>()) {
    if (!charge())
      return set.emitError("port supply inventory exceeds 1048576 work units");
    sets[set.getSymName()] = set;
  }
  for (auto domain : module.getOps<upf::UPFDomainOp>()) {
    if (!charge())
      return domain.emitError(
          "port supply inventory exceeds 1048576 work units");
    Domain fact{domain.getExtentAttr() ? domain.getExtentAttr().getIncluded()
                                       : domain.getElements(),
                domain.getExtentAttr() ? domain.getExtentAttr().getExcluded()
                                       : domain.getExcludedElementsAttr(),
                domain.getPrimaryAttr()};
    if (auto strategies = domain.getRetentionsAttr())
      for (auto value : strategies) {
        auto strategy = cast<upf::RetentionAttr>(value);
        fact.retainedOutput |=
            strategy.getUseRetentionAsPrimary() && !strategy.getNoRetention() &&
            !upf::isStaticallyEmptyRetention(strategy, domain);
      }
    domains.push_back(fact);
  }
  // A declaration's owner is not proof of its actual driver. Retain a small,
  // conservative proof for directly written whole variables. References that
  // escape, helper/partial writes and resolved nets remain unknown; they must
  // pass the different-supply filter rather than suppress isolation.
  bool inventoryExceeded = false;
  llvm::StringMap<sim::SimFuncOp> functions;
  llvm::DenseMap<Operation *, SmallVector<Operation *>> incoming;
  llvm::DenseMap<Operation *, bool> initializationOnly;
  llvm::DenseSet<Operation *> opaqueFunctions;
  llvm::DenseSet<OpOperand *> captureUses;
  SmallVector<std::pair<Value, uint64_t>> references;
  for (auto fn : design.getOps<sim::SimFuncOp>())
    functions[fn.getSymName()] = fn;
  if (auto uses = SymbolTable::getSymbolUses(&design.getBody())) {
    for (const auto &use : *uses) {
      if (!charge()) {
        inventoryExceeded = true;
        break;
      }
      auto found =
          functions.find(use.getSymbolRef().getRootReference().getValue());
      if (found == functions.end())
        continue;
      auto spawn = dyn_cast<sim::SimSpawnOp>(use.getUser());
      auto caller = use.getUser()->getParentOfType<sim::SimFuncOp>();
      bool initializing =
          isa<sim::SimCallOp>(use.getUser()) && caller &&
          caller.getEntryKind() == sim::EntryKind::RootInitializer;
      auto [entry, inserted] =
          initializationOnly.try_emplace(found->second, initializing);
      if (!inserted)
        entry->second &= initializing;
      if (!spawn || spawn.getCallee() != found->getKey())
        opaqueFunctions.insert(found->second);
      else
        incoming[found->second].push_back(spawn);
    }
  } else {
    for (auto fn : design.getOps<sim::SimFuncOp>())
      opaqueFunctions.insert(fn);
  }
  for (auto fn : design.getOps<sim::SimFuncOp>()) {
    if (fn.isExternal())
      continue;
    for (auto argument : fn.getArguments()) {
      if (!charge()) {
        inventoryExceeded = true;
        break;
      }
      if (!isa<sim::RefType>(argument.getType()))
        continue;
      unsigned index = argument.getArgNumber();
      auto kind = fn.getArgAttrOfType<sim::CaptureKindAttr>(
          index, sim::metadata::CaptureKind::getNameStr());
      auto id = fn.getArgAttrOfType<IntegerAttr>(
          index, sim::metadata::DescriptorId::getNameStr());
      if (!id || !kind || kind.getValue() != sim::CaptureKind::Storage)
        continue;
      auto &fact = writers[id.getUInt()];
      bool whole = fn.isPrivate() && !opaqueFunctions.contains(fn) &&
                   !incoming[fn].empty();
      for (StringRef name :
           {sim::metadata::DescriptorRootType::getNameStr(),
            sim::metadata::DescriptorLow::getNameStr(),
            sim::metadata::DescriptorIndices::getNameStr(),
            sim::metadata::DescriptorAggregateType::getNameStr(),
            sim::metadata::DescriptorPackedLow::getNameStr()})
        whole &= !fn.getArgAttr(index, name);
      for (Operation *user : incoming[fn]) {
        if (!charge()) {
          inventoryExceeded = true;
          whole = false;
          break;
        }
        if (index >= user->getNumOperands()) {
          whole = false;
          continue;
        }
        auto actual =
            user->getOperand(index).getDefiningOp<sim::SimContextStorageOp>();
        auto caller = user->getParentOfType<sim::SimFuncOp>();
        if (!actual || actual.getId() != id.getUInt() || !caller ||
            caller.getEntryKind() != sim::EntryKind::RootInitializer)
          whole = false;
      }
      if (!whole) {
        fact.unknown = true;
        continue;
      }
      for (Operation *user : incoming[fn])
        captureUses.insert(&user->getOpOperand(index));
      references.push_back({argument, id.getUInt()});
    }
  }
  design.walk([&](sim::SimContextStorageOp lookup) {
    references.push_back({lookup.getResult(), lookup.getId()});
  });
  llvm::DenseMap<Value, uint64_t> wholeReferences;
  for (auto [reference, id] : references) {
    wholeReferences[reference] = id;
    auto &fact = writers[id];
    for (OpOperand &use : reference.getUses()) {
      if (!charge()) {
        inventoryExceeded = true;
        break;
      }
      Operation *user = use.getOwner();
      if (captureUses.contains(&use))
        continue;
      if (isa<sim::SimRefLoadOp, sim::SimSuspendChangeOp>(user))
        continue;
      Value destination;
      if (auto store = dyn_cast<sim::SimRefStoreOp>(user))
        destination = store.getReference();
      if (auto nba = dyn_cast<sim::SimNBAEnqueueOp>(user))
        destination = nba.getDestination();
      auto fn = user->getParentOfType<sim::SimFuncOp>();
      if (!destination || destination != reference || !fn) {
        fact.unknown = true;
        continue;
      }
      if (fn.getEntryKind() == sim::EntryKind::RootInitializer ||
          fn.getEntryKind() == sim::EntryKind::Initial ||
          (fn.isPrivate() && initializationOnly.lookup(fn)))
        continue;
      auto unit = fn.getCodeUnitId() ? units.lookup(*fn.getCodeUnitId())
                                     : sim::SimCodeUnitDeclOp{};
      switch (fn.getEntryKind()) {
      case sim::EntryKind::Always:
      case sim::EntryKind::AlwaysComb:
      case sim::EntryKind::AlwaysFF:
      case sim::EntryKind::AlwaysLatch:
      case sim::EntryKind::Continuous:
        if (unit)
          fact.scopes.push_back(unit.getScopeId());
        else
          fact.unknown = true;
        break;
      default:
        fact.unknown = true;
        break;
      }
    }
  }
  // The marker identifies a value, not a promise that arbitrary same-width
  // data came from this formal. Prove the marked load's physical root/window
  // before using reflected driver facts or inserting an isolation mux.
  design.walk([&](upf::UPFPortValueOp marker) {
    auto port = actors.lookup(marker.getActor());
    if (!port || port.getSourceIsNet() || port.getSourceLow())
      return;
    Value value = marker.getInput();
    while (true) {
      if (!charge()) {
        inventoryExceeded = true;
        return;
      }
      Value operand;
      if (auto flatten = value.getDefiningOp<sim::SimPackedFlattenOp>())
        operand = flatten.getInput();
      else if (auto unflatten =
                   value.getDefiningOp<sim::SimPackedUnflattenOp>())
        operand = unflatten.getInput();
      else if (auto fromBits = value.getDefiningOp<sim::SimLogicFromBitsOp>())
        operand = fromBits.getInput();
      else
        break;
      auto width = sim::getPackedWidth(value.getType());
      if (!width || width != sim::getPackedWidth(operand.getType()))
        return;
      value = operand;
    }
    auto load = value.getDefiningOp<sim::SimRefLoadOp>();
    auto root = roots.find({false, port.getSourceId()});
    if (load && wholeReferences.count(load.getReference()) &&
        wholeReferences.lookup(load.getReference()) == port.getSourceId() &&
        root != roots.end() &&
        sim::getPackedWidth(port.getType()) == root->second.width &&
        sim::getPackedWidth(marker.getType()) == root->second.width)
      provenPublications.insert(marker.getActor());
  });
  if (inventoryExceeded)
    return design.emitError("port driver inventory exceeds 1048576 work units");
  std::set<StringRef> macros;
  for (auto attrs : module.getOps<upf::UPFDesignAttributesOp>()) {
    if (!charge())
      return attrs.emitError(
          "port supply inventory exceeds 1048576 work units");
    if (attrs.getHardMacro() || attrs.getSoftMacro())
      macros.insert(attrs.getElement().getPath().getValue());
  }
  std::set<StringRef> contexts;
  for (auto inventory : module.getOps<upf::UPFContextsOp>())
    for (auto entry : inventory.getRoots()) {
      if (!charge())
        return inventory.emitError("port contexts exceed 1048576 work units");
      auto root = cast<StringAttr>(entry).getValue();
      if (!semanticScopes.lookup(root))
        return inventory.emitError(
            "port context requires a declared design-top instance");
      contexts.insert(root);
    }
  for (auto domain : module.getOps<upf::UPFDomainOp>())
    if (auto top = domain.getIsolationTop())
      contexts.insert(*top);
  for (auto annotation : ports) {
    if (!charge(annotation.getProperties().size() + 1))
      return annotation.emitError(
          "port attribute checks exceed 1048576 work units");
    if (annotation.getModel())
      continue;
    if (!semanticScopes.count(annotation.getScope()) ||
        !semanticScopes.lookup(annotation.getTop()))
      return annotation.emitError("port attributes require a declared source "
                                  "scope and design-top instance");
    auto found = paths.find(annotation.getPort());
    bool supply = bool(annotation.getDriverSupplyAttr() ||
                       annotation.getReceiverSupplyAttr());
    if (found == paths.end()) {
      if (!supply && annotation.getSourceWidth() == 0)
        continue;
      return annotation.emitError(
          "port attribute consumer requires a reflected packed port");
    }
    auto port = found->second;
    auto width = sim::getPackedWidth(port.getType());
    if (!supply && !annotation.getSourceWidth() && !width)
      continue;
    auto root = roots.find({port.getSourceIsNet(), port.getSourceId()});
    if (!width || *width != annotation.getSourceWidth() ||
        root == roots.end() || port.getSourceLow() > root->second.width ||
        *width > root->second.width - port.getSourceLow())
      return annotation.emitError("port attribute geometry disagrees with its "
                                  "logical declaration or physical source");
    auto &properties = annotations[port.getHierarchicalName()];
    for (auto property : annotation.getProperties())
      properties[property.getName().str()].push_back(annotation);
    if (!supply)
      continue;
    hasSupplies = true;
    auto parent = scopes.lookup(port.getScopeId()).getParent();
    while (parent) {
      if (!charge())
        return annotation.emitError(
            "port terminal checks exceed 1048576 work units");
      auto scope = scopes.lookup(*parent);
      if (!scope)
        return annotation.emitError(
            "port terminal check references an unknown parent scope");
      auto path = scope.getHierarchicalName().value_or(StringRef{});
      if (macros.count(path) && !upf::isWithinPath(annotation.getTop(), path))
        return annotation.emitError(
            "port supply reference crosses macro terminal boundary");
      parent = scope.getParent();
    }
    if (owner(port) != annotation.getScope() &&
        owner(port) != annotation.getTop())
      return annotation.emitError(
          "driver/receiver supply attributes require local instance ports "
          "(IEEE 1801-2018 Table 5)");
    bool terminal = owner(port) == annotation.getTop() ||
                    macros.count(owner(port)) || contexts.count(owner(port));
    if (!terminal)
      continue; // 6.48: ignored on ordinary internal ports.
    auto direction = port.getDirection();
    if (annotation.getDriverSupplyAttr() &&
        direction != sim::PortDirection::Output)
      return annotation.emitError(
          "external driver-supply corruption is not implemented");
    if (direction == sim::PortDirection::InOut)
      return annotation.emitError(
          "inout port supply consumers are not implemented");
    if ((annotation.getDriverSupplyAttr() &&
         direction == sim::PortDirection::Output) ||
        (annotation.getReceiverSupplyAttr() &&
         direction == sim::PortDirection::Input)) {
      auto actual = domain(owner(port));
      if (failed(actual))
        return failure();
      auto proven =
          direction == sim::PortDirection::Output
              ? driver(port)
              : FailureOr<FlatSymbolRefAttr>((*actual) ? (*actual)->primary
                                                       : FlatSymbolRefAttr{});
      if (failed(proven))
        return failure();
      if (!*actual || !(*actual)->primary || (*actual)->retainedOutput ||
          ((*actual)->excluded && !(*actual)->excluded.empty()) || !*proven)
        return annotation.emitError(
            "post-strategy internal port supply or absent-driver corruption "
            "proof is not implemented");
      auto specified = direction == sim::PortDirection::Output
                           ? annotation.getDriverSupplyAttr()
                           : annotation.getReceiverSupplyAttr();
      if (!equal(specified, *proven, false))
        return annotation.emitError(
            "specified port supply differs from its internal supply; "
            "additional equivalence proofs are not implemented");
    }
  }
  for (auto &entry : annotations)
    for (auto &[name, windows] : entry.getValue()) {
      llvm::sort(windows,
                 [](auto a, auto b) { return a.getOffset() < b.getOffset(); });
      uint64_t end = 0;
      for (auto annotation : windows) {
        if (annotation.getOffset() < end)
          return annotation.emitError("resolved port property windows overlap");
        end = annotation.getOffset() + annotation.getWidth();
      }
    }
  return success();
}
sim::SimPortDeclOp PortSupplyAnalysis::portForActor(uint64_t actor) const {
  return actors.lookup(actor);
}
FailureOr<FlatSymbolRefAttr>
PortSupplyAnalysis::driver(sim::SimPortDeclOp port) {
  if (port.getSourceIsNet())
    return FlatSymbolRefAttr{};
  auto root = roots.find({false, port.getSourceId()});
  auto writes = writers.find(port.getSourceId());
  auto actor = formalActors.find(port.getId());
  if (actor != formalActors.end() && !publicationIsProven(actor->second))
    return FlatSymbolRefAttr{};
  if (root == roots.end() || writes == writers.end() ||
      writes->second.unknown || writes->second.scopes.empty())
    return FlatSymbolRefAttr{};
  auto rootScope = scopes.lookup(root->second.scope);
  auto rootPath = rootScope
                      ? rootScope.getHierarchicalName().value_or(StringRef{})
                      : StringRef{};
  if (rootPath.empty() || !upf::isWithinPath(rootPath, owner(port)))
    return FlatSymbolRefAttr{};
  auto actual = domain(rootPath);
  if (failed(actual))
    return failure();
  if (!*actual || !(*actual)->primary || (*actual)->retainedOutput ||
      ((*actual)->excluded && !(*actual)->excluded.empty()))
    return FlatSymbolRefAttr{};
  for (auto scopeID : writes->second.scopes) {
    if (!charge()) {
      port.emitError("port driver proof exceeds 1048576 work units");
      return failure();
    }
    auto scope = scopes.lookup(scopeID);
    auto path =
        scope ? scope.getHierarchicalName().value_or(StringRef{}) : StringRef{};
    if (path.empty() || !upf::isWithinPath(path, owner(port)))
      return FlatSymbolRefAttr{};
    auto writerDomain = domain(path);
    if (failed(writerDomain))
      return failure();
    if (!*writerDomain || (*writerDomain)->retainedOutput ||
        !equal((*actual)->primary, (*writerDomain)->primary, false))
      return FlatSymbolRefAttr{};
  }
  // A collapsed input alias on this same boundary can also supply the root.
  // Descendant input receivers do not establish an external driver here.
  for (auto &entry : paths) {
    if (!charge()) {
      port.emitError("port driver proof exceeds 1048576 work units");
      return failure();
    }
    auto input = entry.second;
    if (input.getScopeId() != port.getScopeId() || input.getSourceIsNet() ||
        input.getDirection() == sim::PortDirection::Output ||
        input.getSourceId() != port.getSourceId())
      continue;
    auto a = sim::getPackedWidth(input.getType());
    auto b = sim::getPackedWidth(port.getType());
    if (!a || !b ||
        (input.getSourceLow() < port.getSourceLow() + *b &&
         port.getSourceLow() < input.getSourceLow() + *a))
      return FlatSymbolRefAttr{};
  }
  return (*actual)->primary;
}
LogicalResult
PortSupplyAnalysis::checkIsolationOutputs(upf::UPFDomainOp current,
                                          ArrayRef<StringRef> boundaries) {
  for (uint64_t id : opaqueOutputs) {
    if (!charge(boundaries.size() + 1))
      return current.emitError(
          "isolation output checks exceed 1048576 work units");
    auto scope = scopes.lookup(id);
    auto path =
        scope ? scope.getHierarchicalName().value_or(StringRef{}) : StringRef{};
    if (llvm::is_contained(boundaries, path))
      return current.emitError("isolation of opaque output ports requires "
                               "logical port views and is not implemented");
  }
  return success();
}
bool PortSupplyAnalysis::inputControl(StringRef path,
                                      ArrayRef<StringRef> boundaries) const {
  auto found = paths.find(path);
  if (found == paths.end())
    return false;
  auto port = found->second;
  auto root = roots.find({port.getSourceIsNet(), port.getSourceId()});
  return port.getDirection() == sim::PortDirection::Input &&
         llvm::is_contained(boundaries, owner(port)) && !port.getSourceLow() &&
         sim::getPackedWidth(port.getType()) == 1 && root != roots.end() &&
         root->second.width == 1;
}
FailureOr<bool> PortSupplyAnalysis::isolate(upf::UPFDomainOp current,
                                            sim::SimPortDeclOp port) {
  auto fail = [&](const llvm::Twine &message) -> FailureOr<bool> {
    current.emitError(message);
    return failure();
  };
  if (!current.getIsolationDiffSupplyOnly())
    return true;
  auto source = driver(port);
  if (failed(source))
    return failure();
  if (!*source)
    return true; // Unknown passes the filter.
  auto context = current.getIsolationTop();
  if (!context || *context != owner(port))
    return true; // General endpoint inference is separate.
  auto topDomain = domain(*context);
  if (failed(topDomain))
    return failure();
  FlatSymbolRefAttr fallback =
      *topDomain ? (*topDomain)->primary : FlatSymbolRefAttr{};
  auto found = annotations.find(port.getHierarchicalName());
  SmallVector<upf::UPFPortAttributesOp> windows;
  if (found != annotations.end())
    if (auto property = found->second.find("UPF_receiver_supply");
        property != found->second.end())
      windows = property->second;
  auto width = sim::getPackedWidth(port.getType());
  if (!width)
    return fail("isolation supply filter requires a packed logical port");
  bool yes = false, no = false;
  uint64_t end = 0;
  auto decide = [&](FlatSymbolRefAttr receiver) {
    auto kind = current.getIsolationUseFunctionalEquivalence()
                    ? upf::SupplyEquivalenceKind::Functional
                    : upf::SupplyEquivalenceKind::Electrical;
    bool applies = !receiver || !equal(*source, receiver, true, kind);
    yes |= applies;
    no |= !applies;
  };
  for (auto annotation : windows) {
    if (!charge())
      return fail("port supply filtering exceeds 1048576 work units");
    if (annotation.getOffset() > end)
      decide(fallback);
    decide(annotation.getReceiverSupplyAttr());
    end = annotation.getOffset() + annotation.getWidth();
  }
  if (end < *width)
    decide(fallback);
  if (yes && no)
    return fail("per-bit isolation filtering requires logical port views and "
                "is not implemented");
  return yes;
}
LogicalResult validateUPFPortAttributes(ModuleOp module) {
  auto designs = module.getOps<sim::SimDesignOp>();
  if (!llvm::hasSingleElement(designs)) {
    if (llvm::any_of(module.getOps<upf::UPFPortAttributesOp>(),
                     [](auto op) { return !op.getModel(); }))
      return module.emitError(
          "port attribute consumers require one simulation design");
    return success();
  }
  PortSupplyAnalysis analysis(module, *designs.begin());
  return analysis.initialize();
}
} // namespace talos
