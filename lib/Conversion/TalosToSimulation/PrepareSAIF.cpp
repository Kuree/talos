//===- PrepareSAIF.cpp - Resolve Annex I RTL activity observations --------===//

#include "talos/Analysis/SimulationAnalysis.h"
#include "talos/Conversion/TalosToSimulation.h"
#include "talos/Dialect/SAIF/SAIFOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringExtras.h"

using namespace mlir;

namespace talos {
#define GEN_PASS_DEF_TALOSSIMPREPARESAIFPASS
#include "talos/Conversion/Passes.h.inc"

namespace {
using saif::IdentifierAttr;
using saif::PathAttr;

// Parse a single *elaborated HDL* name, not SAIF source text. Escaped HDL
// identifiers retain literal dots/brackets; generated instance indices do not.
static IdentifierAttr identifier(MLIRContext *context, StringRef name) {
  bool escaped = name.starts_with("\\");
  if (escaped)
    name = name.drop_front().rtrim();
  StringAttr index;
  if (!escaped && name.ends_with("]")) {
    size_t open = name.rfind('[');
    if (open != StringRef::npos) {
      StringRef number = name.slice(open + 1, name.size() - 1);
      if (!number.empty() && llvm::all_of(number, llvm::isDigit)) {
        index = StringAttr::get(context, number);
        name = name.take_front(open);
      }
    }
  }
  return IdentifierAttr::get(context, StringAttr::get(context, name), index);
}

static PathAttr path(MLIRContext *context, ArrayRef<Attribute> components) {
  return PathAttr::get(context, ArrayAttr::get(context, components));
}

static PathAttr append(PathAttr prefix, PathAttr suffix) {
  SmallVector<Attribute> components(prefix.getComponents().getValue());
  llvm::append_range(components, suffix.getComponents());
  return path(prefix.getContext(), components);
}

static PathAttr qualify(PathAttr prefix, PathAttr name) {
  // Annex I names may already include the root instance.
  if (!prefix || (name.getComponents().size() > 1 &&
                  name.getComponents()[0] == prefix.getComponents()[0]))
    return name;
  return append(prefix, name);
}

struct Candidate {
  Operation *canonical;
  uint64_t id, low;
  bool net, port;
  PathAttr name;
  uint64_t width;
  int64_t right;
  bool ascending, indexed;
  uint32_t initial;
};

struct TalosSimPrepareSAIFPass
    : impl::TalosSimPrepareSAIFPassBase<TalosSimPrepareSAIFPass> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (!saif::has<saif::Output>(module)) {
      markAllAnalysesPreserved();
      return;
    }
    if (saif::has<saif::Bindings>(module)) {
      markAllAnalysesPreserved();
      return;
    }
    MLIRContext *context = &getContext();
    SmallVector<Candidate> candidates;
    DenseMap<PathAttr, size_t> names;
    DenseMap<uint64_t, sim::SimScopeDeclOp> scopes;
    DenseMap<uint64_t, PathAttr> scopePaths;
    DenseSet<uint64_t> pendingScopes;
    bool invalid = false;
    module.walk(
        [&](sim::SimScopeDeclOp scope) { scopes[scope.getId()] = scope; });
    std::function<PathAttr(uint64_t)> scopePath = [&](uint64_t id) -> PathAttr {
      if (auto found = scopePaths.find(id); found != scopePaths.end())
        return found->second;
      auto found = scopes.find(id);
      if (found == scopes.end() || !pendingScopes.insert(id).second)
        return {};
      auto scope = found->second;
      StringRef hierarchy = scope.getHierarchicalName().value_or("");
      SmallVector<Attribute> components;
      if (auto parent = scope.getParent()) {
        auto parentPath = scopePath(*parent);
        auto parentScope = scopes.find(*parent);
        if (parentPath)
          llvm::append_range(components, parentPath.getComponents());
        if (parentScope != scopes.end()) {
          StringRef parentName =
              parentScope->second.getHierarchicalName().value_or("");
          if (hierarchy.consume_front(parentName))
            hierarchy.consume_front(".");
        }
      }
      // $root is an HDL reflection scope, not an Annex I design instance.
      if (scope.getParent() || scope.getDebugName().value_or("") != "$root")
        components.push_back(identifier(context, hierarchy));
      pendingScopes.erase(id);
      if (components.empty())
        return {};
      return scopePaths[id] = path(context, components);
    };

    for (auto design : module.getOps<sim::SimDesignOp>()) {
      DenseMap<uint64_t, Operation *> storages, nets;
      for (auto storage : design.getOps<sim::SimStorageDeclOp>())
        storages[storage.getId()] = storage;
      for (auto net : design.getOps<sim::SimNetDeclOp>())
        nets[net.getId()] = net;
      auto add = [&](Operation *op, Operation *canonical, uint64_t scopeId,
                     uint64_t id, uint64_t low, bool net, bool port, Type type,
                     StringRef debugName) {
        PathAttr scope = scopePath(scopeId);
        auto width = sim::getPackedWidth(type);
        // Annex I RTL points are integral scalar/vector objects. Aggregates
        // and dynamic objects need an explicit future naming/flattening rule.
        bool supported = isa<IntegerType, sim::LogicType>(type);
        int64_t right = 0;
        bool ascending = false;
        bool indexed = width && *width > 1;
        if (auto array = dyn_cast<sim::PackedArrayType>(type)) {
          auto elementWidth = sim::getPackedWidth(array.getElementType());
          supported = elementWidth && *elementWidth == 1 &&
                      isa<IntegerType, sim::LogicType>(array.getElementType());
          right = array.getRight();
          ascending = array.getLeft() < right;
          indexed = true;
          supported &= array.getLeft() >= 0 && right >= 0;
        }
        if (!scope || debugName.empty() || !supported || !width || !*width)
          return;
        SmallVector<Attribute> components(scope.getComponents().getValue());
        // Declaration debug names are already decoded HDL identifiers.
        // Brackets here are literal (e.g. escaped SV \\q[0] ), not a select.
        components.push_back(IdentifierAttr::get(
            context, StringAttr::get(context, debugName), StringAttr{}));
        PathAttr name = path(context, components);
        uint32_t initial = analysis::containsFourStateLogic(type) ? 2 : 0;
        if (auto netDecl = dyn_cast<sim::SimNetDeclOp>(canonical)) {
          switch (netDecl.getResolutionKind()) {
          case sim::NetResolutionKind::Supply0:
          case sim::NetResolutionKind::Tri0:
            initial = 0;
            break;
          case sim::NetResolutionKind::Supply1:
          case sim::NetResolutionKind::Tri1:
            initial = 1;
            break;
          case sim::NetResolutionKind::TriReg:
            break;
          default:
            initial = initial == 2 ? 3 : 0;
            break;
          }
        }
        Candidate candidate{canonical, id,    low,       net,     port,   name,
                            *width,    right, ascending, indexed, initial};
        auto [it, inserted] = names.try_emplace(name, candidates.size());
        if (inserted)
          candidates.push_back(candidate);
        else if (port)
          candidates[it->second] = candidate;
      };
      for (auto storage : design.getOps<sim::SimStorageDeclOp>())
        if (storage.getLifetime() == sim::Lifetime::Design &&
            !sim::has<sim::metadata::SubroutineStorage>(storage) &&
            cov::has<cov::SourceAuthored>(storage))
          add(storage, storage, storage.getScopeId(), storage.getId(), 0, false,
              false, storage.getType(), storage.getDebugName().value_or(""));
      for (auto net : design.getOps<sim::SimNetDeclOp>())
        if (net.getLifetime() == sim::Lifetime::Design &&
            !net->hasAttr("internal") && cov::has<cov::SourceAuthored>(net))
          add(net, net, net.getScopeId(), net.getId(), 0, true, false,
              net.getType(), net.getDebugName().value_or(""));
      for (auto port : design.getOps<sim::SimPortDeclOp>()) {
        Operation *canonical = port.getSourceIsNet()
                                   ? nets.lookup(port.getSourceId())
                                   : storages.lookup(port.getSourceId());
        if (canonical && cov::has<cov::SourceAuthored>(port))
          add(port, canonical, port.getScopeId(), port.getSourceId(),
              port.getSourceLow(), port.getSourceIsNet(), true, port.getType(),
              port.getDebugName().value_or(""));
      }
    }

    SmallVector<Attribute> bindings;
    auto bind = [&](const Candidate &candidate, PathAttr target, bool port,
                    StringAttr virtualType, std::optional<uint64_t> selected,
                    Operation *site) {
      auto components = target.getComponents().getValue();
      if (components.size() < 2) {
        site->emitError("SAIF mapped signal needs a containing instance");
        invalid = true;
        return;
      }
      auto leaf = cast<IdentifierAttr>(components.back());
      if (leaf.getIndex() && !selected && candidate.width != 1) {
        site->emitError("a whole SAIF vector cannot map to a single bit");
        invalid = true;
        return;
      }
      uint64_t count = selected ? 1 : candidate.width;
      if (bindings.size() + count > (1 << 20)) {
        site->emitError("SAIF inventory exceeds 1048576 bits");
        invalid = true;
        return;
      }
      PathAttr instance = path(context, components.drop_back());
      for (uint64_t i = 0; i < count; ++i) {
        uint64_t bit = selected.value_or(i);
        IdentifierAttr signal = leaf;
        if (!leaf.getIndex() && candidate.indexed && !selected) {
          int64_t index = candidate.right +
                          (candidate.ascending ? -int64_t(bit) : int64_t(bit));
          signal =
              IdentifierAttr::get(context, leaf.getName(),
                                  StringAttr::get(context, Twine(index).str()));
        }
        bindings.push_back(saif::BindingAttr::get(
            context, candidate.id, candidate.net, candidate.low + bit, instance,
            signal, port, candidate.initial, virtualType));
      }
      sim::mark<sim::metadata::TransitionObservable>(candidate.canonical);
    };

    SmallVector<saif::FileOp> files(module.getOps<saif::FileOp>());
    if (files.empty()) {
      for (const Candidate &candidate : candidates)
        bind(candidate, candidate.name, candidate.port, {}, {},
             candidate.canonical);
    } else {
      for (saif::FileOp file : files) {
        bool libraryForm = false;
        for (auto header : file.getBody().front().getOps<saif::HeaderOp>())
          if (header.getKind() == saif::HeaderKind::Direction &&
              header.getText().value_or("") != "forward") {
            header.emitError("SAIF collection input must be RTL forward SAIF");
            invalid = true;
          } else if (header.getKind() == saif::HeaderKind::Version &&
                     header.getQualifierAttr())
            libraryForm = true;
        file.walk([&](saif::LibraryOp library) { libraryForm = true; });
        if (libraryForm) {
          file.emitError("library forward SAIF collection (SDPD/glitch "
                         "directives) is not implemented");
          invalid = true;
        }
        std::function<void(saif::InstanceOp, PathAttr)> visit =
            [&](saif::InstanceOp instance, PathAttr parent) {
              PathAttr prefix = qualify(parent, instance.getName());
              auto map = [&](saif::MappingOp mapping) {
                PathAttr source = qualify(prefix, mapping.getSourceName());
                std::optional<uint64_t> selected;
                auto found = names.find(source);
                if (found == names.end()) {
                  SmallVector<Attribute> components(
                      source.getComponents().getValue());
                  auto leaf = cast<IdentifierAttr>(components.back());
                  if (leaf.getIndex()) {
                    uint64_t index;
                    if (!leaf.getIndex().getValue().getAsInteger(10, index) &&
                        index <= INT64_MAX) {
                      components.back() = IdentifierAttr::get(
                          context, leaf.getName(), StringAttr{});
                      found = names.find(path(context, components));
                      if (found != names.end()) {
                        const Candidate &candidate = candidates[found->second];
                        int64_t bit = candidate.ascending
                                          ? candidate.right - int64_t(index)
                                          : int64_t(index) - candidate.right;
                        if (candidate.indexed && bit >= 0 &&
                            uint64_t(bit) < candidate.width)
                          selected = bit;
                        else
                          found = names.end();
                      }
                    }
                  }
                }
                if (found == names.end()) {
                  mapping.emitError("SAIF source does not resolve to a "
                                    "supported scalar/vector bit: ")
                      << source;
                  invalid = true;
                  return;
                }
                bind(candidates[found->second],
                     qualify(prefix, mapping.getMappedName()),
                     isa<saif::PortsOp>(mapping->getParentOp()),
                     mapping.getVirtualTypeAttr(), selected, mapping);
              };
              for (Operation &container : instance.getBody().front())
                if (isa<saif::PortsOp, saif::NetsOp>(container))
                  for (auto mapping :
                       container.getRegion(0).front().getOps<saif::MappingOp>())
                    map(mapping);
              for (auto child :
                   instance.getBody().front().getOps<saif::InstanceOp>())
                visit(child, prefix);
            };
        for (auto instance : file.getBody().front().getOps<saif::InstanceOp>())
          visit(instance, {});
      }
    }
    if (invalid)
      return signalPassFailure();
    auto plan = ArrayAttr::get(context, bindings);
    // Validate the prepared plan even when inter-pass verification is off.
    // Name collisions and virtual-instance structure belong to the dialect.
    auto *dialect = context->getLoadedDialect<saif::SAIFDialect>();
    if (failed(dialect->verifyOperationAttribute(
            module,
            NamedAttribute(
                StringAttr::get(context, saif::Bindings::getNameStr()), plan))))
      return signalPassFailure();
    saif::set<saif::Bindings>(module, plan);
    for (auto file : files)
      file.erase();
  }
};
} // namespace
} // namespace talos
