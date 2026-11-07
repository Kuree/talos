// Resolve ownership once in the compiler; simulation uses ordinary guards.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/STLExtras.h"
#include <algorithm>
#include <map>
#include <optional>

using namespace mlir;
namespace talos {
LogicalResult resolveUPFDomainExtents(ModuleOp module) {
  SmallVector<upf::UPFDomainOp> domains(module.getOps<upf::UPFDomainOp>());
  struct Selection {
    SmallVector<unsigned, 2> included, excluded;
    upf::UPFDesignAttributesOp hardMacro;
  };
  std::map<StringRef, Selection, upf::InstancePathLess> selections;
  if (!domains.empty())
    for (auto annotation : module.getOps<upf::UPFDesignAttributesOp>())
      if (annotation.getHardMacro())
        selections[annotation.getElement().getPath().getValue()].hardMacro =
            annotation;
  for (auto [index, domain] : llvm::enumerate(domains)) {
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
  SmallVector<SmallVector<Attribute>> included(domains.size()),
      excluded(domains.size());
  Builder builder(module.getContext());
  for (auto &[path, selection] : selections) {
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
        auto diagnostic = domains[index].emitError()
                          << "design instance is selected by multiple power "
                             "domains: "
                          << path;
        diagnostic.attachNote(domains[*owner].getLoc())
            << "also explicitly selected by " << domains[*owner].getSymName();
        return failure();
      }
      owner = index;
    }
    bool excludesParent =
        parent && std::binary_search(selection.excluded.begin(),
                                     selection.excluded.end(), *parent);
    // 6.20: hard macros never inherit their parent's physical owner. Until
    // anonymous domains are represented, fail before applying parent-domain
    // retention obligations or atomic minimum-extent checks to their state.
    if (selection.hardMacro && parent) {
      if (owner == parent)
        return selection.hardMacro.emitError(
            "hard macro cannot be explicitly selected in its parent's power "
            "domain (IEEE 1801-2018 6.20)");
      if (!owner)
        return selection.hardMacro.emitError(
            "anonymous hard-macro power domains are not implemented; the macro "
            "needs a separate explicit power domain");
    }
    // 5.7.2/6.20/8.3.3: atomic minimum extents are established before
    // non-atomic partitioning, after aggregate updates have been collapsed.
    // A tree sweep is equivalent: no explicit descendant claim can displace
    // inherited atomic ownership, except at that atomic domain's own hole.
    if (owner && parent && *owner != *parent && domains[*parent].getAtomic() &&
        !excludesParent) {
      auto diagnostic = domains[*owner].emitError()
                        << "cannot partition atomic power domain "
                        << domains[*parent].getSymName() << " at " << path;
      diagnostic.attachNote(domains[*parent].getLoc())
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
  // Diagnose all conflicts before mutating any extent, including a rerun.
  for (auto [index, domain] : llvm::enumerate(domains))
    domain.setExtentAttr(upf::DomainExtentAttr::get(
        module.getContext(), builder.getArrayAttr(included[index]),
        builder.getArrayAttr(excluded[index])));
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
