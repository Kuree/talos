#include "RetentionSelection.h"
#include "PowerState.h"
#include "llvm/ADT/STLExtras.h"
#include <limits>

using namespace mlir;
namespace talos {
using namespace upf_detail;
RetentionSelection::RetentionSelection(sim::SimDesignOp design)
    : design(design), module(design->getParentOfType<ModuleOp>()) {
  for (auto scope : design.getOps<sim::SimScopeDeclOp>()) {
    StringRef path = scope.getHierarchicalName().value_or(StringRef{});
    scopes[scope.getId()] = {
        path, scope.getParent(),
        bool(scope.getDefinitionName() || scope.getVpiDefinitionAttr() ||
             scope.getInterfaceType() || !scope.getParent())};
    if (!path.empty())
      scopeIDs[path] = scope.getId();
  }
  domains.assign(module.getOps<upf::UPFDomainOp>().begin(),
                 module.getOps<upf::UPFDomainOp>().end());
}
bool RetentionSelection::charge(size_t count) {
  if (count > 1048576 - work) {
    exceeded = true;
    return false;
  }
  work += count;
  return true;
}
bool RetentionSelection::within(uint64_t scope, uint64_t root) const {
  auto a = intervals.find(scope), b = intervals.find(root);
  return a != intervals.end() && b != intervals.end() &&
         b->second.first <= a->second.first &&
         a->second.first < b->second.second;
}
uint64_t RetentionSelection::lexicalScope(StringRef path, uint64_t fallback) {
  auto found = scopePaths.upper_bound(path);
  if (found == scopePaths.begin())
    return fallback;
  uint64_t id = std::prev(found)->second;
  while (charge()) {
    auto scope = scopes.lookup(id);
    if (!scope.path.empty() && upf::isWithinPath(path, scope.path))
      return id;
    if (!scope.parent)
      break;
    id = *scope.parent;
  }
  return fallback;
}
upf::UPFDomainOp RetentionSelection::domain(StringRef path) const {
  for (auto domain : domains)
    if (contains(domain, path))
      return domain;
  return {};
}
unsigned
RetentionSelection::specificity(upf::RetentionElementAttr element) const {
  if (element.getKind() == upf::RetentionElementKind::Signal)
    return std::numeric_limits<unsigned>::max();
  if (element.getKind() == upf::RetentionElementKind::Process)
    return std::numeric_limits<unsigned>::max() - 1;
  auto id = scopeIDs.find(element.getPath().getValue());
  return id == scopeIDs.end() ? 0 : 2 + depths.lookup(id->second);
}
bool RetentionSelection::matches(upf::RetentionElementAttr element,
                                 const RetentionRegister &reg, bool direct,
                                 bool domainOnly) const {
  StringRef path = element.getPath().getValue();
  if (element.getKind() == upf::RetentionElementKind::Process)
    return llvm::is_contained(reg.processes, path);
  auto root = scopeIDs.find(path);
  if (element.getKind() == upf::RetentionElementKind::Instance) {
    auto declaration = reg.declaration;
    uint64_t scope = storageScopes.lookup(declaration.getId());
    return root != scopeIDs.end() && within(scope, root->second) &&
           (!direct || owners.lookup(scope) == owners.lookup(root->second));
  }
  for (const auto &alias : reg.aliases) {
    if (domainOnly && reg.domain && !contains(reg.domain, alias.path))
      continue;
    if (element.getKind() == upf::RetentionElementKind::Signal) {
      if (path == alias.path)
        return true;
    }
  }
  return false;
}
bool RetentionSelection::filter(
    upf::RetentionElementAttr element,
    std::optional<upf::RetentionFilter> choice) const {
  if (!choice)
    return true;
  auto annotation = annotations.lookup(element);
  auto value = annotation ? annotation.getRetention() : std::nullopt;
  switch (*choice) {
  case upf::RetentionFilter::Required:
    return value == upf::RetentionPurpose::Required;
  case upf::RetentionFilter::Optional:
    return value == upf::RetentionPurpose::Optional;
  case upf::RetentionFilter::NotRequired:
    return value != upf::RetentionPurpose::Required;
  case upf::RetentionFilter::NotOptional:
    return value != upf::RetentionPurpose::Optional;
  }
  llvm_unreachable("verified retention filter");
}
LogicalResult RetentionSelection::expand(Group &group) {
  auto declaration = group.declaration;
  llvm::DenseMap<uint64_t, bool> explicitMarks;
  auto mark = [&](ArrayAttr elements, bool include) -> LogicalResult {
    for (auto attr : elements) {
      if (!charge())
        return failure();
      auto element = cast<upf::RetentionElementAttr>(attr);
      if (element.getKind() != upf::RetentionElementKind::Instance)
        continue;
      auto found = scopeIDs.find(element.getPath().getValue());
      if (found == scopeIDs.end())
        return declaration.emitError(
                   "retention list references an unknown instance: ")
               << element.getPath();
      explicitMarks[found->second] = include;
    }
    return success();
  };
  if (failed(mark(declaration.getElements(), true)) ||
      failed(mark(declaration.getExcluded(), false)))
    return failure();
  llvm::DenseMap<uint64_t, bool> inheritedMarks = explicitMarks;
  auto included = [&](uint64_t id) {
    SmallVector<uint64_t> chain;
    bool result = false;
    while (charge()) {
      if (auto found = inheritedMarks.find(id); found != inheritedMarks.end()) {
        result = found->second;
        break;
      }
      chain.push_back(id);
      auto scope = scopes.lookup(id);
      if (!declaration.getTransitive() || !scope.parent)
        break;
      id = *scope.parent;
    }
    for (auto child : chain)
      inheritedMarks[child] = result;
    return result;
  };
  for (auto attr : declaration.getElements()) {
    auto origin = cast<upf::RetentionElementAttr>(attr);
    if (origin.getKind() != upf::RetentionElementKind::Instance) {
      if (!llvm::is_contained(declaration.getExcluded(), origin) &&
          filter(origin, declaration.getAppliesTo())) {
        if (!charge())
          return failure();
        group.members.push_back({origin, origin});
      }
      continue;
    }
    SmallVector<uint64_t> pending{
        scopeIDs.find(origin.getPath().getValue())->second};
    while (!pending.empty()) {
      if (!charge())
        return failure();
      uint64_t id = pending.pop_back_val();
      auto element = upf::RetentionElementAttr::get(
          module->getContext(),
          StringAttr::get(module->getContext(), scopes.lookup(id).path),
          upf::RetentionElementKind::Instance);
      bool selected = included(id);
      if (exceeded)
        return failure();
      if (!selected || !filter(element, declaration.getAppliesTo()))
        continue;
      group.members.push_back({element, origin});
      auto annotation = annotations.lookup(element);
      if (declaration.getTransitive() &&
          !(annotation &&
            (annotation.getHardMacro() || annotation.getSoftMacro())))
        llvm::append_range(pending, children.lookup(id));
    }
  }
  for (auto member : group.members)
    if (member.element.getKind() == upf::RetentionElementKind::Process)
      requestedProcesses.insert(member.element.getPath().getValue());
  // An excluded process still needs its producer closure when an instance
  // (or another process) could imply its state. Explicit signals outrank
  // process exclusions and need no such closure on their own.
  if (llvm::any_of(group.members, [](Member member) {
        return member.origin.getKind() != upf::RetentionElementKind::Signal;
      }))
    for (auto attr : declaration.getExcluded()) {
      auto element = cast<upf::RetentionElementAttr>(attr);
      if (element.getKind() == upf::RetentionElementKind::Process)
        requestedProcesses.insert(element.getPath().getValue());
    }
  return success();
}
LogicalResult RetentionSelection::initialize() {
  // The semantic hierarchy keeps generate scopes even when Simulation
  // reflection elides them. Private compiler IDs never enter runtime inventory.
  uint64_t nextScope = 0;
  for (auto [id, scope] : scopes)
    nextScope = std::max(nextScope, id + 1);
  bool sawHierarchy = false;
  for (auto hierarchy : module.getOps<upf::UPFHierarchyOp>()) {
    if (sawHierarchy)
      return hierarchy.emitError("duplicate semantic HDL hierarchy");
    sawHierarchy = true;
    for (auto attr : hierarchy.getScopes()) {
      if (!charge())
        return hierarchy.emitError(
            "retention list resolution exceeds 1048576 work units");
      auto scope = cast<upf::HierarchyScopeAttr>(attr);
      StringRef path = scope.getPath().getValue();
      if (!scopeIDs.count(path)) {
        scopeIDs[path] = nextScope;
        scopes[nextScope++] = {path, {}, scope.getInstance()};
      }
    }
    for (auto attr : hierarchy.getScopes()) {
      auto source = cast<upf::HierarchyScopeAttr>(attr);
      auto &scope = scopes[scopeIDs.lookup(source.getPath().getValue())];
      scope.instance = source.getInstance();
      scope.parent = source.getParent().getValue().empty()
                         ? std::nullopt
                         : std::optional<uint64_t>(
                               scopeIDs.lookup(source.getParent().getValue()));
    }
  }
  llvm::DenseMap<uint64_t, SmallVector<uint64_t>> lexicalChildren;
  SmallVector<uint64_t> roots;
  for (auto [id, scope] : scopes) {
    if (!scope.path.empty())
      scopePaths[scope.path] = id;
    if (scope.parent) {
      if (!scopes.count(*scope.parent))
        return design.emitError("retention scope references an unknown parent");
      lexicalChildren[*scope.parent].push_back(id);
    } else
      roots.push_back(id);
  }
  // DFS intervals make ancestry independent of IDs/order and constant-time in
  // every physical projection. Build all owners before the instance graph.
  struct Visit {
    uint64_t id, owner;
    unsigned depth;
    bool exit;
  };
  SmallVector<Visit> pending;
  for (auto id : roots)
    pending.push_back({id, id, 1, false});
  size_t clock = 0;
  while (!pending.empty()) {
    if (!charge())
      return design.emitError(
          "retention list resolution exceeds 1048576 work units");
    auto [id, owner, depth, exit] = pending.pop_back_val();
    if (exit) {
      intervals[id].second = clock;
      continue;
    }
    if (owners.count(id))
      return design.emitError("cyclic retention scope hierarchy");
    auto scope = scopes.lookup(id);
    owners[id] = scope.instance ? id : owner;
    depths[id] = depth;
    intervals[id].first = clock++;
    pending.push_back({id, owners.lookup(id), depth, true});
    for (auto child : lexicalChildren.lookup(id))
      pending.push_back({child, owners.lookup(id), depth + 1, false});
  }
  if (owners.size() != scopes.size())
    return design.emitError("cyclic retention scope hierarchy");
  for (auto [id, scope] : scopes)
    if (scope.instance && scope.parent) {
      uint64_t parent = *scope.parent;
      while (true) {
        if (!charge())
          return design.emitError(
              "retention list resolution exceeds 1048576 work units");
        children[parent].push_back(id);
        auto node = scopes.lookup(parent);
        if (node.instance || !node.parent)
          break;
        parent = *node.parent;
      }
    }
  for (auto declaration : design.getOps<sim::SimStorageDeclOp>())
    if (auto path = declaration.getHierarchicalName())
      storageScopes[declaration.getId()] =
          lexicalScope(*path, declaration.getScopeId());
  for (auto annotation : module.getOps<upf::UPFDesignAttributesOp>()) {
    if (!charge())
      return annotation.emitError(
          "retention list resolution exceeds 1048576 work units");
    if (!annotations.try_emplace(annotation.getElement(), annotation).second)
      return annotation.emitError("duplicate attributes for one HDL object");
    if (annotation.getElement().getKind() ==
            upf::RetentionElementKind::Process &&
        annotation.getRetention() == upf::RetentionPurpose::Required)
      requestedProcesses.insert(annotation.getElement().getPath().getValue());
  }
  for (auto declaration : module.getOps<upf::UPFRetentionElementsOp>()) {
    if (groups.size() >= 4096)
      return declaration.emitError("design exceeds 4096 retention lists");
    groupIDs[FlatSymbolRefAttr::get(declaration.getSymNameAttr())] =
        groups.size();
    groups.push_back({declaration, {}, {}});
    if (failed(expand(groups.back())))
      return exceeded
                 ? declaration.emitError(
                       "retention list resolution exceeds 1048576 work units")
                 : failure();
  }
  for (auto domain : domains)
    if (auto strategies = domain.getRetentionsAttr())
      for (auto attr : strategies) {
        auto strategy = cast<upf::RetentionAttr>(attr);
        for (auto selectors : {strategy.getElements(), strategy.getExcluded()})
          for (auto attr : selectors)
            if (auto selector = dyn_cast<upf::RetentionElementAttr>(attr))
              if (selector.getKind() == upf::RetentionElementKind::Process)
                requestedProcesses.insert(selector.getPath().getValue());
      }
  return success();
}
unsigned RetentionSelection::groupRank(Group &group,
                                       const RetentionRegister &reg,
                                       bool &partial) {
  if (exceeded)
    return 0;
  unsigned included = 0, excluded = 0, precedence = 0;
  for (auto member : group.members) {
    if (!charge(1 + reg.aliases.size() + reg.processes.size()) ||
        !matches(member.element, reg, true))
      continue;
    unsigned spec = specificity(member.origin);
    if (spec < included)
      continue;
    included = spec;
    auto kind = member.origin.getKind();
    auto declaration = reg.declaration;
    auto root = scopeIDs.find(member.origin.getPath().getValue());
    unsigned rank =
        kind == upf::RetentionElementKind::Signal    ? 5u
        : kind == upf::RetentionElementKind::Process ? 4u
        : root != scopeIDs.end() &&
                root->second ==
                    owners.lookup(storageScopes.lookup(declaration.getId()))
            ? 3u
            : 2u;
    precedence = std::max(precedence, rank);
    for (auto alias : reg.aliases)
      partial |= kind == upf::RetentionElementKind::Signal && alias.partial &&
                 alias.path == member.element.getPath().getValue();
  }
  for (auto attr : group.declaration.getExcluded()) {
    auto element = cast<upf::RetentionElementAttr>(attr);
    if (!charge(1 + reg.aliases.size() + reg.processes.size()))
      break;
    if (matches(element, reg))
      excluded = std::max(excluded, specificity(element));
  }
  return included > excluded ? precedence : 0;
}
unsigned RetentionSelection::rank(upf::RetentionAttr strategy,
                                  const RetentionRegister &reg, bool &partial) {
  unsigned included = strategy.getDomainDefault() ? 1 : 0, excluded = 0;
  unsigned precedence = included;
  auto declaration = reg.declaration;
  auto owner = owners.lookup(storageScopes.lookup(declaration.getId()));
  for (auto attr : strategy.getElements()) {
    if (auto reference = dyn_cast<FlatSymbolRefAttr>(attr)) {
      auto found = groupIDs.find(reference);
      if (found != groupIDs.end()) {
        bool groupPartial = false;
        unsigned rank = groupRank(groups[found->second], reg, groupPartial);
        if (rank) {
          partial |= groupPartial;
          precedence = std::max(precedence, rank);
          // Keep the original granularity for subsequent strategy exclusions.
          // The group has already resolved its own inclusion/exclusion marks.
          for (auto member : groups[found->second].members)
            if (matches(member.element, reg, true))
              included = std::max(included, specificity(member.origin));
        }
      }
      continue;
    }
    auto element = cast<upf::RetentionElementAttr>(attr);
    if (!matches(element, reg, false, true))
      continue;
    included = std::max(included, specificity(element));
    auto kind = element.getKind();
    auto root = scopeIDs.find(element.getPath().getValue());
    precedence = std::max(
        precedence, kind == upf::RetentionElementKind::Signal         ? 5u
                    : kind == upf::RetentionElementKind::Process      ? 4u
                    : root != scopeIDs.end() && root->second == owner ? 3u
                                                                      : 2u);
    for (auto alias : reg.aliases)
      partial |= kind == upf::RetentionElementKind::Signal && alias.partial &&
                 alias.path == element.getPath().getValue();
  }
  for (auto attr : strategy.getExcluded()) {
    auto element = cast<upf::RetentionElementAttr>(attr);
    if (matches(element, reg, false, true))
      excluded = std::max(excluded, specificity(element));
  }
  return included > excluded ? precedence : 0;
}
void RetentionSelection::record(const RetentionRegister &reg) {
  states.push_back(reg);
}
namespace {
StringRef statePath(const RetentionRegister &reg) {
  auto declaration = reg.declaration;
  return *declaration.getHierarchicalName();
}
Attribute conditionKey(upf::ExpressionAttr expression) {
  if (!expression)
    return {};
  if (expression.getTokens().size() == 1) {
    auto token = cast<upf::ExpressionTokenAttr>(expression.getTokens()[0]);
    if (token.getOpcode() == upf::ExpressionOpcode::Constant &&
        token.getUnknown().getValue().isZero())
      return BoolAttr::get(expression.getContext(),
                           !token.getValue().getValue().isZero());
  }
  return expression;
}
} // namespace
namespace {
// These interned keys are compiler-local, never printed into IR. Sorting
// uniqued attributes produces the same conjunction key regardless of catalog
// traversal order without serializing potentially large policy expressions.
ArrayAttr conjunction(MLIRContext *ctx, SmallVector<Attribute> entries) {
  llvm::sort(entries, [](Attribute a, Attribute b) {
    return std::less<const void *>{}(a.getAsOpaquePointer(),
                                     b.getAsOpaquePointer());
  });
  entries.erase(std::unique(entries.begin(), entries.end()), entries.end());
  return ArrayAttr::get(ctx, entries);
}
} // namespace
ArrayAttr RetentionSelection::policyKey(FlatSymbolRefAttr ref) {
  if (auto found = supplyKeys.find(ref); found != supplyKeys.end())
    return found->second;
  SmallVector<Attribute> keys;
  for (auto set : getRetentionSupplyPolicies(module, ref, &symbols,
                                             [&] { return charge(); })) {
    SmallVector<Attribute> required(set.getRequired().begin(),
                                    set.getRequired().end());
    if (!charge(required.size()))
      return {};
    llvm::sort(required, [](Attribute a, Attribute b) {
      return cast<StringAttr>(a).getValue() < cast<StringAttr>(b).getValue();
    });
    NamedAttrList functions;
    for (auto name : required) {
      auto function = cast<StringAttr>(name);
      Attribute root = set.getFunctions().get(function);
      // An immutable FULL_ON root has the same normal-state behavior as any
      // other immutable FULL_ON root when no voltage/state catalog observes it.
      if (!set.getStatesAttr() || set.getStatesAttr().empty())
        if (auto supply = symbols.lookupNearestSymbolFrom<upf::UPFSupplyOp>(
                module, cast<FlatSymbolRefAttr>(root));
            supply && supply.getAlwaysOn())
          root = BoolAttr::get(module->getContext(), true);
      functions.set(function, root);
    }
    if (auto states = set.getStatesAttr()) {
      size_t count = 0;
      states.walk([&](Attribute) { ++count; });
      if (!charge(count))
        return {};
    }
    keys.push_back(ArrayAttr::get(
        module->getContext(),
        {functions.getDictionary(module->getContext()),
         set.getStatesAttr() ? set.getStatesAttr()
                             : ArrayAttr::get(module->getContext(), {}),
         BoolAttr::get(module->getContext(), set.getComplete())}));
  }
  auto result = conjunction(module->getContext(), std::move(keys));
  supplyKeys[ref] = result;
  return result;
}
ArrayAttr RetentionSelection::domainKey(upf::UPFDomainOp domain) {
  if (auto found = domainKeys.find(domain); found != domainKeys.end())
    return found->second;
  auto unit = UnitAttr::get(module->getContext());
  SmallVector<Attribute> policies;
  if (auto entries = domain.getPoliciesAttr())
    for (auto ref : entries) {
      auto key = policyKey(cast<FlatSymbolRefAttr>(ref));
      if (!key || !charge(key.size()))
        return {};
      llvm::append_range(policies, key.getValue());
    }
  auto present = [&](Attribute attr) -> Attribute {
    return attr ? attr : unit;
  };
  auto result = ArrayAttr::get(
      module->getContext(),
      {domain.getPowerAttr(), present(domain.getGroundAttr()),
       present(domain.getInputAttr()), domain.getOn(),
       present(domain.getPartialAttr()), present(domain.getOffAttr()),
       present(domain.getErrorsAttr()),
       conjunction(module->getContext(), std::move(policies))});
  domainKeys[domain] = result;
  return result;
}
ArrayAttr RetentionSelection::storageKey(const RetentionRegister &reg) {
  auto id = std::pair<Attribute, Operation *>{reg.strategy, reg.domain};
  if (auto found = storageKeys.find(id); found != storageKeys.end())
    return found->second;
  auto strategy = reg.strategy;
  auto primary = policyKey(strategy.getPrimarySupply());
  auto retention = policyKey(strategy.getRetentionSupply());
  auto domain = domainKey(reg.domain);
  if (!primary || !retention || !domain || !charge())
    return {};
  auto present = [&](Attribute attr) -> Attribute {
    return attr ? attr : UnitAttr::get(module->getContext());
  };
  auto condition = [&](upf::ExpressionAttr attr) -> Attribute {
    auto key = conditionKey(attr);
    return key ? key : BoolAttr::get(module->getContext(), true);
  };
  auto result = ArrayAttr::get(
      module->getContext(),
      {domain, primary, retention, present(strategy.getSave()),
       present(strategy.getRestore()), condition(strategy.getSaveCondition()),
       condition(strategy.getRestoreCondition()),
       condition(strategy.getCondition()),
       BoolAttr::get(module->getContext(),
                     strategy.getRetentionSupplyCorrupt()),
       BoolAttr::get(module->getContext(), strategy.getSaveRestoreCorrupt())});
  storageKeys[id] = result;
  return result;
}
bool RetentionSelection::equivalent(const RetentionRegister &a,
                                    const RetentionRegister &b) {
  if (a.strategy == b.strategy && a.domain == b.domain)
    return true;
  auto x = storageKey(a), y = storageKey(b);
  return x && y && x == y;
}
LogicalResult RetentionSelection::validate() {
  llvm::DenseSet<Operation *> retainedDomains;
  for (const auto &reg : states)
    if (reg.strategy && !reg.strategy.getNoRetention())
      retainedDomains.insert(reg.domain);
  for (const auto &reg : states) {
    bool retained = reg.strategy && !reg.strategy.getNoRetention();
    auto domain = reg.domain;
    if (domain && domain.getRetentionsAttr() &&
        !domain.getRetentionsAttr().empty() && !retained)
      for (auto [element, annotation] : annotations) {
        if (!charge(1 + reg.aliases.size() + reg.processes.size()))
          return design.emitError(
              "retention list resolution exceeds 1048576 work units");
        if (annotation.getRetention() == upf::RetentionPurpose::Required &&
            matches(cast<upf::RetentionElementAttr>(element), reg, true))
          return annotation.emitError(
                     "UPF_retention=required state is not retained by a domain "
                     "strategy (IEEE 1801-2018 5.6): ")
                 << statePath(reg);
      }
    for (auto &group : groups) {
      bool partial = false;
      if (groupRank(group, reg, partial))
        group.states.push_back(&reg);
    }
  }
  if (exceeded)
    return design.emitError(
        "retention list resolution exceeds 1048576 work units");
  for (auto &group : groups) {
    const RetentionRegister *policy = nullptr;
    for (const auto *reg : group.states) {
      bool retained = reg->strategy && !reg->strategy.getNoRetention();
      if (retained)
        policy = reg;
      if (!retained && reg->domain &&
          group.declaration.getPurpose() == upf::RetentionPurpose::Required &&
          retainedDomains.contains(reg->domain))
        return group.declaration.emitError(
                   "required collective retention list has uncovered state in "
                   "a domain with retained elements (IEEE 1801-2018 6.51): ")
               << statePath(*reg);
    }
    if (!policy)
      continue;
    for (const auto *reg : group.states) {
      if (!reg->strategy || reg->strategy.getNoRetention())
        return group.declaration.emitError(
                   "collective retention list has uncovered state while "
                   "another member is retained (IEEE 1801-2018 6.51): ")
               << statePath(*reg);
      if (!equivalent(*policy, *reg)) {
        if (exceeded)
          return group.declaration.emitError(
              "retention list resolution exceeds 1048576 work units");
        return group.declaration.emitError(
                   "collective retention coherence for differing storage "
                   "policies is not implemented: ")
               << statePath(*policy) << " and " << statePath(*reg);
      }
    }
  }
  return success();
}
} // namespace talos
