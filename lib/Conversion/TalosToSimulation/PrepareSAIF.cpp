//===- PrepareSAIF.cpp - Resolve Annex I RTL activity observations --------===//

#include "PrepareSAIFLibrary.h"
#include "talos/Analysis/NativeStorageLayout.h"
#include "talos/Analysis/SimulationAnalysis.h"
#include "talos/Conversion/TalosToSimulation.h"
#include "talos/Dialect/SAIF/SAIFOps.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringSet.h"

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
  uint64_t scopeId;
  bool output;
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
    DenseMap<Operation *, analysis::DefaultStoragePlanes> defaults;
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
        if (!scope || debugName.empty())
          return;
        if (!net && !defaults.count(canonical)) {
          Type rootType = cast<sim::SimStorageDeclOp>(canonical).getType();
          defaults.try_emplace(canonical,
                               analysis::getDefaultStoragePlanes(rootType));
        }
        bool output = !port || cast<sim::SimPortDeclOp>(op).getDirection() !=
                                   sim::PortDirection::Input;
        std::function<void(Type, std::string, uint64_t, unsigned,
                           std::optional<int64_t>)>
            enumerate;
        enumerate = [&](Type leafType, std::string leafName, uint64_t offset,
                        unsigned depth, std::optional<int64_t> leafIndex) {
          if (depth > 128 || candidates.size() > (1 << 20)) {
            op->emitError(
                "SAIF aggregate inventory exceeds its resource limit");
            invalid = true;
            return;
          }
          auto width = sim::getPackedWidth(leafType);
          bool scalar = isa<IntegerType, sim::LogicType>(leafType);
          int64_t left = width ? int64_t(*width) - 1 : 0, right = 0;
          bool indexed = width && *width > 1;
          if (auto array = dyn_cast<sim::PackedArrayType>(leafType)) {
            auto elementWidth = sim::getPackedWidth(array.getElementType());
            scalar = elementWidth && *elementWidth == 1 &&
                     isa<IntegerType, sim::LogicType>(array.getElementType());
            left = array.getLeft();
            right = array.getRight();
            indexed = true;
          }
          if (scalar && width && *width && left >= 0 && right >= 0) {
            SmallVector<Attribute> components(scope.getComponents().getValue());
            components.push_back(IdentifierAttr::get(
                context, StringAttr::get(context, leafName),
                leafIndex ? StringAttr::get(context, Twine(*leafIndex).str())
                          : StringAttr{}));
            PathAttr name = path(context, components);
            uint32_t initial =
                analysis::containsFourStateLogic(leafType) ? 2 : 0;
            if (auto declaration = dyn_cast<sim::SimNetDeclOp>(canonical)) {
              switch (declaration.getResolutionKind()) {
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
            Candidate candidate{canonical,    id,      offset,  net,
                                port,         name,    *width,  right,
                                left < right, indexed, initial, scopeId,
                                output};
            auto [it, inserted] = names.try_emplace(name, candidates.size());
            if (inserted)
              candidates.push_back(candidate);
            else {
              const auto &previous = candidates[it->second];
              if (previous.canonical != canonical || previous.low != offset ||
                  previous.width != *width || previous.net != net) {
                op->emitError(
                    "SAIF flattened name collides with another declaration: ")
                    << name;
                invalid = true;
              } else if (port)
                candidates[it->second] = candidate;
            }
            return;
          }
          if (!sim::isAggregateType(leafType))
            return;
          ArrayAttr fields;
          if (auto record = dyn_cast<sim::PackedStructType>(leafType))
            fields = record.getFields();
          else if (auto record = dyn_cast<sim::UnpackedStructType>(leafType))
            fields = record.getFields();
          else if (auto record = dyn_cast<sim::PackedUnionType>(leafType))
            fields = record.getFields();
          else if (auto record = dyn_cast<sim::UnpackedUnionType>(leafType))
            fields = record.getFields();
          int64_t arrayLeft = 0, arrayRight = 0;
          if (auto array = dyn_cast<sim::PackedArrayType>(leafType)) {
            arrayLeft = array.getLeft();
            arrayRight = array.getRight();
          } else if (auto array = dyn_cast<sim::UnpackedArrayType>(leafType)) {
            arrayLeft = array.getLeft();
            arrayRight = array.getRight();
          }
          unsigned count = sim::getAggregateNumElements(leafType);
          if (count > (1 << 20)) {
            op->emitError("SAIF aggregate inventory exceeds 1048576 elements");
            invalid = true;
            return;
          }
          for (unsigned ordinal = 0; ordinal < count; ++ordinal) {
            auto geometry =
                sim::getAggregateProvenanceSubelement(leafType, ordinal);
            if (!geometry || geometry->first > UINT64_MAX - offset)
              continue;
            std::string suffix;
            auto elementType = sim::getAggregateElementType(leafType, ordinal);
            int64_t elementIndex =
                arrayLeft + (arrayLeft <= arrayRight ? int64_t(ordinal)
                                                     : -int64_t(ordinal));
            bool finalIndex = !fields && elementIndex >= 0 &&
                              !sim::isAggregateType(elementType) &&
                              sim::getPackedWidth(elementType) == 1;
            if (fields)
              suffix = "." + cast<sim::FieldAttr>(fields[ordinal])
                                 .getName()
                                 .getValue()
                                 .str();
            else if (!finalIndex)
              suffix = "[" + Twine(elementIndex).str() + "]";
            enumerate(elementType, leafName + suffix, offset + geometry->first,
                      depth + 1,
                      finalIndex ? std::optional<int64_t>(elementIndex)
                                 : std::nullopt);
          }
        };
        enumerate(type, debugName.str(), low, 0, std::nullopt);
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
    SmallVector<uint8_t> outputs;
    DenseSet<std::tuple<PathAttr, IdentifierAttr, uint32_t>> mappedPoints;
    auto bind = [&](const Candidate &candidate, PathAttr target, bool port,
                    StringAttr virtualType, std::optional<uint64_t> selected,
                    Operation *site, bool fillMissing = false) {
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
        auto key = std::make_tuple(instance, signal, uint32_t(port));
        if (fillMissing && mappedPoints.contains(key))
          continue;
        mappedPoints.insert(key);
        uint32_t initial = candidate.initial;
        if (!candidate.net) {
          const auto &planes = defaults.find(candidate.canonical)->second;
          uint64_t position = candidate.low + bit;
          if (position >= planes.value.getBitWidth()) {
            site->emitError(
                "SAIF aggregate bit exceeds its native storage layout");
            invalid = true;
            return;
          }
          initial = unsigned(planes.value[position]) |
                    (unsigned(planes.unknown[position]) << 1);
        }
        bindings.push_back(saif::BindingAttr::get(
            context, candidate.id, candidate.net, candidate.low + bit, instance,
            signal, port, initial, virtualType));
        outputs.push_back(candidate.output);
      }
      sim::mark<sim::metadata::TransitionObservable>(candidate.canonical);
    };

    SmallVector<saif::FileOp> files(module.getOps<saif::FileOp>());
    bool hasRTL = llvm::any_of(files, [](saif::FileOp file) {
      return !file.getBody().front().getOps<saif::InstanceOp>().empty();
    });
    for (auto file : files)
      for (auto header : file.getBody().front().getOps<saif::HeaderOp>())
        if (header.getKind() == saif::HeaderKind::Direction &&
            header.getText().value_or("") != "forward") {
          header.emitError("SAIF collection input must be forward SAIF");
          invalid = true;
        }
    if (!hasRTL) {
      for (const Candidate &candidate : candidates)
        bind(candidate, candidate.name, candidate.port, {}, {},
             candidate.canonical);
    } else {
      for (saif::FileOp file : files) {
        for (auto header : file.getBody().front().getOps<saif::HeaderOp>())
          if (header.getKind() == saif::HeaderKind::Direction &&
              header.getText().value_or("") != "forward") {
            header.emitError("SAIF collection input must be RTL forward SAIF");
            invalid = true;
          }

        std::function<void(saif::InstanceOp, PathAttr)> visit =
            [&](saif::InstanceOp instance, PathAttr parent) {
              PathAttr prefix = qualify(parent, instance.getName());
              auto findSource = [&](PathAttr source) {
                auto found = names.find(source);
                auto components = source.getComponents();
                // HDL aggregate members are flattened into the SAIF signal
                // basename. Preserve the final canonical array/bit select.
                for (size_t first = 1;
                     found == names.end() && first + 1 < components.size();
                     ++first) {
                  std::string basename;
                  for (size_t i = first; i < components.size(); ++i) {
                    auto item = cast<IdentifierAttr>(components[i]);
                    if (i != first)
                      basename += '.';
                    basename += item.getName().getValue();
                    if (i + 1 < components.size() && item.getIndex())
                      basename += "[" + item.getIndex().getValue().str() + "]";
                  }
                  SmallVector<Attribute> flattened(components.begin(),
                                                   components.begin() + first);
                  flattened.push_back(IdentifierAttr::get(
                      context, StringAttr::get(context, basename),
                      cast<IdentifierAttr>(components[components.size() - 1])
                          .getIndex()));
                  found = names.find(path(context, flattened));
                }
                return found;
              };
              auto map = [&](saif::MappingOp mapping) {
                PathAttr source = qualify(prefix, mapping.getSourceName());
                std::optional<uint64_t> selected;
                auto found = findSource(source);
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
                      found = findSource(path(context, components));
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
    llvm::StringSet<> libraryTypes;
    for (auto file : files)
      file.walk([&](saif::CellOp cell) {
        libraryTypes.insert(
            cast<IdentifierAttr>(cell.getName().getComponents()[0])
                .getName()
                .getValue());
      });
    for (const Candidate &candidate : candidates) {
      // Conditions can name every cell pin, including pins not selected by
      // an RTL activity mapping. Bind these once in the original instance.
      if (candidate.port && scopes.count(candidate.scopeId)) {
        auto definition = scopes.lookup(candidate.scopeId).getDefinitionName();
        if (definition && libraryTypes.contains(*definition))
          bind(candidate, candidate.name, true, {}, {}, candidate.canonical,
               true);
      }
      // Provenance must also survive intermediate, unselected source roots.
      sim::mark<sim::metadata::TransitionObservable>(candidate.canonical);
    }
    auto cellPlan =
        prepareSAIFLibrary(module, files, scopePaths, bindings, outputs);
    if (failed(cellPlan))
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
    saif::set<saif::Cells>(module, *cellPlan);
    if (failed(dialect->verifyOperationAttribute(
            module,
            NamedAttribute(StringAttr::get(context, saif::Cells::getNameStr()),
                           *cellPlan))))
      return signalPassFailure();
    for (auto file : files)
      file.erase();
  }
};
} // namespace
} // namespace talos
