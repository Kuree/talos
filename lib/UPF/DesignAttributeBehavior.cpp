#include "mlir/IR/BuiltinOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/STLExtras.h"
#include <map>

using namespace mlir;
namespace talos {
LogicalResult validateUPFDesignAttributeBehavior(ModuleOp module) {
  SmallVector<upf::UPFDomainOp> domains(module.getOps<upf::UPFDomainOp>());
  size_t work = 0;
  std::map<StringRef, upf::UPFDesignAttributesOp> macros;
  for (auto annotation : module.getOps<upf::UPFDesignAttributesOp>())
    if (annotation.getHardMacro() || annotation.getSoftMacro())
      macros[annotation.getElement().getPath().getValue()] = annotation;
  bool isolation = llvm::any_of(
      domains, [](auto domain) { return bool(domain.getIsolationControl()); });
  if (!macros.empty() && isolation) {
    // Parent placement needs semantic component links: splitting printed HDL
    // paths on dots would mistake characters in escaped identifiers for scopes.
    std::map<StringRef, StringRef> parents;
    std::map<StringRef, bool> instances;
    bool sourceHierarchy = false;
    for (auto hierarchy : module.getOps<upf::UPFHierarchyOp>()) {
      if (sourceHierarchy)
        return hierarchy.emitError(
            "isolation context requires one semantic HDL hierarchy");
      sourceHierarchy = true;
      for (auto entry : hierarchy.getScopes()) {
        if (++work > 1048576)
          return hierarchy.emitError(
              "isolation context checks exceed 1048576 work units");
        auto scope = cast<upf::HierarchyScopeAttr>(entry);
        parents[scope.getPath().getValue()] = scope.getParent().getValue();
        instances[scope.getPath().getValue()] = scope.getInstance();
      }
    }
    if (!sourceHierarchy) {
      std::map<uint64_t, sim::SimScopeDeclOp> scopes;
      module.walk(
          [&](sim::SimScopeDeclOp scope) { scopes[scope.getId()] = scope; });
      for (auto [id, scope] : scopes) {
        if (++work > 1048576)
          return scope.emitError(
              "isolation context checks exceed 1048576 work units");
        auto path = scope.getHierarchicalName();
        if (!path)
          continue;
        StringRef parent;
        auto current = scope.getParent();
        while (current) {
          if (++work > 1048576)
            return scope.emitError(
                "isolation context checks exceed 1048576 work units");
          auto found = scopes.find(*current);
          if (found == scopes.end())
            return scope.emitError(
                "isolation context references an unknown parent scope");
          if (auto name = found->second.getHierarchicalName()) {
            parent = *name;
            break;
          }
          current = found->second.getParent();
        }
        parents[*path] = parent;
        instances[*path] = bool(scope.getDefinitionName() ||
                                scope.getInterfaceType() || !scope.getParent());
      }
    }
    for (auto domain : domains) {
      if (!domain.getIsolationControl())
        continue;
      auto top = domain.getIsolationTop();
      if (top && (!instances.count(*top) || !instances.at(*top)))
        return domain.emitError(
            "isolation context requires a known design-top instance");
      auto extent = domain.getExtentAttr();
      auto boundaries = extent ? extent.getIncluded() : domain.getElements();
      for (auto entry : boundaries) {
        StringRef boundary = cast<StringAttr>(entry).getValue();
        auto found = parents.find(boundary);
        if (found == parents.end())
          return domain.emitError("isolation placement requires semantic "
                                  "hierarchy for the boundary instance");
        // The supported -location parent starts at the boundary's parent.
        // A strategy on an entire macro therefore remains an interface edit.
        StringRef placement = found->second;
        while (!placement.empty()) {
          if (++work > 1048576)
            return domain.emitError(
                "isolation context checks exceed 1048576 work units");
          if (macros.count(placement) &&
              (!top || !upf::isWithinPath(*top, placement)))
            return domain.emitError(
                       "isolation placement crosses macro terminal boundary: ")
                   << placement;
          auto parent = parents.find(placement);
          if (parent == parents.end())
            return domain.emitError("isolation placement requires semantic "
                                    "hierarchy for every ancestor");
          placement = parent->second;
        }
      }
    }
  }
  for (auto annotation : module.getOps<upf::UPFDesignAttributesOp>()) {
    auto values = annotation.getPropertiesAttr();
    auto string = [&](StringRef name) {
      return values ? values.getAs<StringAttr>(name) : StringAttr{};
    };
    auto behavior = string("UPF_simstate_behavior");
    auto aware = string("UPF_is_power_aware_model");
    StringRef mode = behavior                              ? behavior.getValue()
                     : aware && aware.getValue() == "TRUE" ? "DISABLE"
                                                           : "ENABLE";
    if (mode == "PORT_CORR_ONLY" && !annotation.getHardMacro())
      return annotation.emitError(
          "PORT_CORR_ONLY requires UPF_is_hard_macro TRUE");
    if (mode != "DISABLE" && mode != "PORT_CORR_ONLY" &&
        !(mode == "ENABLE" && annotation.getHardMacro()))
      continue;
    if (domains.size() > 1048576 - work)
      return annotation.emitError(
          "design behavior checks exceed 1048576 work units");
    work += domains.size();
    StringRef path = annotation.getElement().getPath().getValue();
    bool live = llvm::any_of(
        domains, [path](auto domain) { return domain.containsPath(path); });
    // Signals and processes can alias powered storage or drive state outside
    // their lexical domain. Until that physical behavior analysis exists, do
    // not discard a disabled policy merely because its printed path is outside.
    if ((mode == "DISABLE" || mode == "PORT_CORR_ONLY") &&
        annotation.getElement().getKind() !=
            upf::RetentionElementKind::Instance)
      live = !domains.empty();
    if (!live)
      continue;
    if (mode == "DISABLE" || mode == "PORT_CORR_ONLY")
      return annotation.emitError(
          "per-object disabled simstate semantics are not implemented; "
          "the design attribute cannot be ignored in a powered domain");
    return annotation.emitError(
        "hard-macro port corruption requires related-supply semantics and is "
        "not implemented");
  }
  return success();
}
} // namespace talos
