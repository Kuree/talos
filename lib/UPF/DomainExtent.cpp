// Resolve ownership once in the compiler; simulation uses ordinary guards.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include <algorithm>
#include <map>
#include <optional>

using namespace mlir;
namespace talos {
LogicalResult resolveUPFDomainExtents(ModuleOp module) {
  if (failed(validateUPFCompositeDomains(module)))
    return failure();
  if (module.getOps<upf::UPFDomainOp>().empty())
    return success();
  size_t work = 0;
  auto charge = [&](size_t count = 1) {
    if (count > 1048576 - work)
      return false;
    work += count;
    return true;
  };
  struct Plan {
    upf::UPFDomainOp domain;
    // Only synthesized domains have a parent and a single macro root.
    std::optional<unsigned> parent;
    StringAttr root;
    StringAttr name;
  };
  SmallVector<Plan> plans;
  std::map<StringRef, upf::UPFDomainOp> existingAnonymous;
  llvm::StringSet<> names;
  for (Operation &op : module.getBody()->getOperations()) {
    if (!charge())
      return module.emitError("domain ownership exceeds 1048576 work units");
    if (auto name =
            op.getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName()))
      names.insert(name.getValue());
  }
  for (auto domain : module.getOps<upf::UPFDomainOp>()) {
    if (!charge(1 + domain.getElements().size() +
                (domain.getExcludedElementsAttr()
                     ? domain.getExcludedElementsAttr().size()
                     : 0)))
      return domain.emitError("domain ownership exceeds 1048576 work units");
    if (!domain.getAnonymousParentAttr()) {
      plans.push_back({domain, {}, {}, domain.getSymNameAttr()});
      continue;
    }
    if (domain.getElements().size() != 1)
      return domain.emitError("anonymous domain requires one hard-macro root");
    auto root = cast<StringAttr>(domain.getElements()[0]);
    if (!existingAnonymous.emplace(root.getValue(), domain).second)
      return domain.emitError("duplicate anonymous hard-macro domain");
  }
  struct Selection {
    SmallVector<unsigned, 2> included, excluded;
    upf::UPFDesignAttributesOp hardMacro;
  };
  std::map<StringRef, Selection, upf::InstancePathLess> selections;
  if (!plans.empty())
    for (auto annotation : module.getOps<upf::UPFDesignAttributesOp>()) {
      if (!charge())
        return annotation.emitError(
            "domain ownership exceeds 1048576 work units");
      if (annotation.getHardMacro())
        selections[annotation.getElement().getPath().getValue()].hardMacro =
            annotation;
    }
  for (unsigned index = 0; index < plans.size(); ++index) {
    auto &plan = plans[index];
    auto domain = plan.domain;
    for (auto element : domain.getElements())
      selections[cast<StringAttr>(element).getValue()].included.push_back(
          index);
    if (auto excluded = domain.getExcludedElementsAttr())
      for (auto element : excluded)
        selections[cast<StringAttr>(element).getValue()].excluded.push_back(
            index);
  }
  struct Boundary {
    StringRef path;
    std::optional<unsigned> owner;
  };
  SmallVector<Boundary> ancestors;
  SmallVector<SmallVector<Attribute>> included(plans.size()),
      excluded(plans.size());
  Builder builder(module.getContext());
  for (auto &[path, selection] : selections) {
    if (!charge(1 + selection.included.size() + selection.excluded.size()))
      return module.emitError("domain ownership exceeds 1048576 work units");
    while (!ancestors.empty() &&
           !upf::isWithinPath(path, ancestors.back().path))
      ancestors.pop_back();
    std::optional<unsigned> parent =
        ancestors.empty() ? std::nullopt : ancestors.back().owner;
    std::optional<unsigned> owner;
    // 5.9: an exclusion wins at the same instance; a deeper explicit include
    // survives an ancestor exclusion. Keep raw selectors for later updates.
    llvm::sort(selection.included);
    llvm::sort(selection.excluded);
    for (unsigned index : selection.included) {
      if (std::binary_search(selection.excluded.begin(),
                             selection.excluded.end(), index))
        continue;
      if (owner && *owner != index) {
        auto diagnostic = plans[index].domain.emitError()
                          << "design instance is selected by multiple power "
                             "domains: "
                          << path;
        diagnostic.attachNote(plans[*owner].domain.getLoc())
            << "also explicitly selected by "
            << plans[*owner].domain.getSymName();
        return failure();
      }
      owner = index;
    }
    bool excludesParent =
        parent && std::binary_search(selection.excluded.begin(),
                                     selection.excluded.end(), *parent);
    // 6.20's specific hard-macro ownership rule establishes structural cuts
    // before an ancestor's atomic minimum is computed. A separate explicit
    // macro owner has the same cut; an ordinary explicit child does not.
    bool hardBoundary = bool(selection.hardMacro);
    if (hardBoundary) {
      if (parent && owner == parent)
        return selection.hardMacro.emitError(
            "hard macro cannot be explicitly selected in its parent's power "
            "domain (IEEE 1801-2018 6.20)");
      if (!owner) {
        if (!parent)
          return selection.hardMacro.emitError(
              "anonymous hard-macro domain requires an owned parent instance");
        auto root = builder.getStringAttr(path);
        auto found = existingAnonymous.find(path);
        upf::UPFDomainOp domain = found == existingAnonymous.end()
                                      ? upf::UPFDomainOp{}
                                      : found->second;
        StringAttr name;
        if (domain) {
          name = domain.getSymNameAttr();
          existingAnonymous.erase(found);
        } else {
          std::string base = ("$anonymous:" + path).str(), candidate = base;
          for (uint64_t suffix = 0; names.contains(candidate); ++suffix) {
            if (!charge())
              return selection.hardMacro.emitError(
                  "anonymous domain names exceed 1048576 work units");
            candidate = base + "_" + std::to_string(suffix);
          }
          names.insert(candidate);
          name = builder.getStringAttr(candidate);
        }
        owner = plans.size();
        plans.push_back({domain, parent, root, name});
        included.emplace_back();
        excluded.emplace_back();
      }
    }
    // 5.7.2/6.20/8.3.3: atomic minimum extents are established before
    // non-atomic partitioning, after aggregate updates have been collapsed.
    // A tree sweep is equivalent: no explicit descendant claim can displace
    // inherited atomic ownership, except at that atomic domain's own hole.
    if (!hardBoundary && owner && parent && *owner != *parent &&
        !plans[*parent].parent && plans[*parent].domain.getAtomic() &&
        !excludesParent) {
      auto diagnostic = plans[*owner].domain.emitError()
                        << "cannot partition atomic power domain "
                        << plans[*parent].domain.getSymName() << " at " << path;
      diagnostic.attachNote(plans[*parent].domain.getLoc())
          << "atomic minimum extent declared here";
      return failure();
    }
    if (!owner && parent && !excludesParent)
      owner = parent;
    // 4.4.2/6.20: inheritance follows immediate parent ownership, not any
    // ancestor domain. An excluded child cannot fall back through another
    // domain to its grandparent. Only an explicit include can re-enter.
    if (parent != owner) {
      auto boundary = builder.getStringAttr(path);
      if (parent)
        excluded[*parent].push_back(boundary);
      if (owner)
        included[*owner].push_back(boundary);
    }
    ancestors.push_back({path, owner});
  }
  // Re-resolution can remove stale derived owners. Check external users once
  // before mutation; surviving derived parent links are refreshed below.
  if (!existingAnonymous.empty()) {
    auto uses = SymbolTable::getSymbolUses(&module.getBodyRegion());
    if (!uses)
      return module.emitError(
          "cannot prove stale anonymous-domain symbol uses");
    SymbolTableCollection symbols;
    llvm::DenseSet<Operation *> stale;
    llvm::DenseSet<Operation *> checkedUsers;
    for (auto &[path, domain] : existingAnonymous)
      stale.insert(domain);
    for (const auto &use : *uses) {
      if (!charge())
        return module.emitError("domain ownership exceeds 1048576 work units");
      auto *target = symbols.lookupNearestSymbolFrom(
          use.getUser(),
          FlatSymbolRefAttr::get(use.getSymbolRef().getRootReference()));
      if (!target || !stale.contains(target))
        continue;
      auto derived = dyn_cast<upf::UPFDomainOp>(use.getUser());
      if (!derived || derived.getAnonymousParentAttr() != use.getSymbolRef())
        return use.getUser()->emitError(
            "references a stale anonymous hard-macro domain");
      if (!checkedUsers.insert(derived).second)
        continue;
      // The typed parent link is refreshed. A second use in custom metadata
      // is a separate reference and must not become dangling after erasure.
      bool extraUse = false;
      auto result =
          derived->getDiscardableAttrDictionary().walk([&](Attribute attr) {
            if (!charge())
              return WalkResult::interrupt();
            if (auto ref = dyn_cast<SymbolRefAttr>(attr))
              if (ref.getRootReference() ==
                  use.getSymbolRef().getRootReference()) {
                extraUse = true;
                return WalkResult::interrupt();
              }
            return WalkResult::advance();
          });
      if (result.wasInterrupted())
        return derived.emitError(
            extraUse ? "references a stale anonymous hard-macro domain in "
                       "custom metadata"
                     : "domain ownership exceeds 1048576 work units");
    }
  }
  // All ownership, names and stale-use checks precede mutation. Parents are
  // materialized before nested anonymous children. Supply objects are shared:
  // this adds no roots, public aliases, switch writers or strategy catalogs.
  OpBuilder opBuilder(module.getContext());
  opBuilder.setInsertionPointToEnd(module.getBody());
  for (unsigned index = 0; index < plans.size(); ++index) {
    auto &plan = plans[index];
    auto domain = plan.domain;
    if (plan.parent) {
      auto parent = plans[*plan.parent].domain;
      auto parentRef = FlatSymbolRefAttr::get(parent.getSymNameAttr());
      if (!domain) {
        domain = upf::UPFDomainOp::create(
            opBuilder, parent.getLoc(), plan.name.getValue(),
            builder.getArrayAttr({plan.root}), parent.getPowerAttr().getValue(),
            parent.getGroundAttr(), FlatSymbolRefAttr{},
            parent.getPrimaryAttr(), parent.getPoliciesAttr(),
            builder.getArrayAttr({}), ArrayAttr{}, upf::SwitchStateAttr{},
            ArrayAttr{}, StringAttr{}, true, 0, ArrayAttr{}, StringAttr{}, true,
            ArrayAttr{}, upf::DomainExtentAttr{}, false, StringAttr{},
            parentRef);
        SymbolTable::setSymbolVisibility(domain,
                                         SymbolTable::Visibility::Private);
        plan.domain = domain;
      } else {
        domain.setAnonymousParentAttr(parentRef);
        domain.setPowerAttr(parent.getPowerAttr());
        domain.setGroundAttr(parent.getGroundAttr());
        domain.setPrimaryAttr(parent.getPrimaryAttr());
        domain.setPoliciesAttr(parent.getPoliciesAttr());
      }
    }
    domain.setExtentAttr(upf::DomainExtentAttr::get(
        module.getContext(), builder.getArrayAttr(included[index]),
        builder.getArrayAttr(excluded[index])));
  }
  for (auto &[path, domain] : existingAnonymous)
    domain.erase();
  return success();
}
namespace {
struct ResolveUPFDomainExtentsPass
    : PassWrapper<ResolveUPFDomainExtentsPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ResolveUPFDomainExtentsPass)
  StringRef getArgument() const final { return "resolve-upf-domains"; }
  StringRef getDescription() const final {
    return "Resolve IEEE 1801 domain selections into exclusive instance "
           "extents";
  }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<upf::UPFDialect>();
  }
  void runOnOperation() override {
    if (failed(resolveUPFDomainExtents(getOperation())))
      signalPassFailure();
  }
};
} // namespace
std::unique_ptr<Pass> createResolveUPFDomainExtentsPass() {
  return std::make_unique<ResolveUPFDomainExtentsPass>();
}
} // namespace talos
