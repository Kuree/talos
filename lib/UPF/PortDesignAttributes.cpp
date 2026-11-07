#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/STLExtras.h"
#include <map>

using namespace mlir;
namespace talos {
LogicalResult normalizeUPFPortDesignAttributes(ModuleOp module) {
  // Predefined signal policies share the design-attribute consumers. Resolve
  // the entire logical port first: forwarding each property/window separately
  // would produce duplicate retention selectors or silently lose partial bits.
  using Windows = SmallVector<upf::UPFPortAttributesOp>;
  std::map<StringRef, std::map<StringRef, Windows>> ports;
  size_t work = 0;
  for (auto op : module.getOps<upf::UPFPortAttributesOp>()) {
    if (op.getModel())
      continue;
    for (StringRef name : {"UPF_retention", "UPF_simstate_behavior"})
      if (op.getProperties().get(name)) {
        if (++work > 1048576)
          return op.emitError(
              "port policy normalization exceeds 1048576 work units");
        ports[op.getPort()][name].push_back(op);
      }
  }
  if (ports.empty())
    return success();
  std::map<StringRef, upf::UPFDesignAttributesOp> existing;
  for (auto op : module.getOps<upf::UPFDesignAttributesOp>()) {
    if (++work > 1048576)
      return op.emitError(
          "port policy normalization exceeds 1048576 work units");
    if (op.getElement().getKind() != upf::RetentionElementKind::Signal ||
        !ports.count(op.getElement().getPath().getValue()))
      continue;
    if (!existing.emplace(op.getElement().getPath().getValue(), op).second)
      return op.emitError("duplicate design policy for a logical port");
  }
  struct Pending {
    upf::UPFDesignAttributesOp previous;
    upf::UPFPortAttributesOp source;
    DictionaryAttr properties;
    upf::RetentionPurposeAttr retention;
  };
  SmallVector<Pending> pending;
  for (auto &[path, properties] : ports) {
    auto previous = existing[path];
    NamedAttrList merged(previous ? previous.getPropertiesAttr()
                                  : DictionaryAttr{});
    auto retention =
        previous ? previous.getRetentionAttr() : upf::RetentionPurposeAttr{};
    upf::UPFPortAttributesOp source;
    for (auto &[name, windows] : properties) {
      llvm::sort(windows,
                 [](auto a, auto b) { return a.getOffset() < b.getOffset(); });
      source = windows.front();
      Attribute value = source.getProperties().get(name);
      uint64_t end = 0, width = source.getSourceWidth();
      for (auto window : windows) {
        if (window.getOffset() != end || window.getSourceWidth() != width ||
            window.getProperties().get(name) != value)
          return window.emitError("partial or differing per-bit predefined "
                                  "port policies are not implemented");
        end += window.getWidth();
      }
      if (end != width)
        return source.emitError(
            "partial predefined port policies are not implemented");
      if (auto old = merged.get(name); old && old != value)
        return source.emitError(
            "port policy disagrees with an existing design policy");
      merged.set(name, value);
      if (name == "UPF_retention") {
        auto purpose = upf::RetentionPurposeAttr::get(
            module.getContext(), *upf::symbolizeRetentionPurpose(
                                     cast<StringAttr>(value).getValue()));
        if (retention && retention != purpose)
          return source.emitError(
              "port retention disagrees with an existing design policy");
        retention = purpose;
      }
    }
    pending.push_back({previous, source,
                       merged.getDictionary(module.getContext()), retention});
  }
  // Commit only after all logical ports have passed preflight. Repeated source
  // and raw-MLIR entry points are idempotent and retain one selector per
  // signal.
  OpBuilder builder(module.getBodyRegion());
  for (auto &entry : pending) {
    if (entry.previous) {
      entry.previous.setPropertiesAttr(entry.properties);
      if (entry.retention)
        entry.previous.setRetentionAttr(entry.retention);
      continue;
    }
    auto source = entry.source;
    upf::UPFDesignAttributesOp::create(
        builder, source.getLoc(),
        upf::RetentionElementAttr::get(module.getContext(),
                                       source.getPortAttr(),
                                       upf::RetentionElementKind::Signal),
        entry.retention, false, false, entry.properties, source.getScopeAttr(),
        source.getTopAttr());
  }
  return success();
}
} // namespace talos
