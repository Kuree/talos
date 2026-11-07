#include "PortAttributes.h"
#ifdef TALOS_ENABLE_UPF
#include "DesignAttributes.h"
#include "talos/Dialect/Slang/SlangOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringMap.h"
#include <array>
#include <set>

using namespace mlir;
namespace talos {
namespace {
StringRef text(Tcl_Obj *object) {
  Tcl_Size size;
  const char *data = Tcl_GetStringFromObj(object, &size);
  return StringRef(data, size);
}
int portError(Tcl_Interp *interp, const llvm::Twine &message) {
  Tcl_SetObjResult(interp, Tcl_NewStringObj(message.str().c_str(), -1));
  Tcl_SetErrorCode(interp, "TALOS", "UPF", nullptr);
  return TCL_ERROR;
}
bool simpleName(StringRef name) {
  for (size_t i = 0; i < name.size(); ++i) {
    if (name[i] == '\\') {
      if (++i == name.size())
        return false;
    } else if (name[i] == '/')
      return false;
  }
  return !name.empty();
}
std::string encodedDeclarationName(StringRef name) {
  std::string result;
  for (char ch : name) {
    if (StringRef("/.\\[]").contains(ch))
      result += '\\';
    result += ch;
  }
  return result;
}
std::string normalizedRequestName(StringRef name) {
  std::string result;
  for (size_t i = 0; i < name.size(); ++i) {
    if (name[i] == '\\' && i + 1 < name.size()) {
      char ch = name[++i];
      if (StringRef("/.\\[]").contains(ch))
        result += '\\';
      result += ch;
    } else
      result += name[i];
  }
  return result;
}
} // namespace
PortAttributes::PortAttributes(
    ModuleOp module, const DesignQuery &queries,
    const std::map<std::string, Operation *> &objects)
    : module(module), queries(queries), objects(objects) {}
bool PortAttributes::charge(size_t count) {
  if (count > 1048576 - work) {
    exceeded = true;
    return false;
  }
  work += count;
  return true;
}
FailureOr<SmallVector<PortAttributes::Segment>>
PortAttributes::resolve(ArrayRef<Source> sources,
                        llvm::function_ref<void(const llvm::Twine &)> report) {
  struct Event {
    unsigned source;
    bool start;
  };
  std::map<uint64_t, SmallVector<Event, 2>> events;
  if (!charge(sources.size() * 2)) {
    report("port attributes exceed 1048576 work units");
    return failure();
  }
  for (auto [index, source] : llvm::enumerate(sources)) {
    events[source.low].push_back({unsigned(index), true});
    events[source.low + source.width].push_back({unsigned(index), false});
  }
  std::array<llvm::DenseMap<Attribute, std::set<unsigned>>, 8> active;
  SmallVector<Segment> result;
  for (auto it = events.begin(); it != events.end(); ++it) {
    if (!charge(it->second.size() + 8)) {
      report("port attributes exceed 1048576 work units");
      return failure();
    }
    for (auto event : it->second) {
      const auto &source = sources[event.source];
      auto &rank = active[source.precedence];
      if (event.start)
        rank[source.value].insert(event.source);
      else {
        auto found = rank.find(source.value);
        found->second.erase(event.source);
        if (found->second.empty())
          rank.erase(found);
      }
    }
    auto next = std::next(it);
    if (next == events.end())
      break;
    for (auto &rank : llvm::reverse(active)) {
      if (rank.empty())
        continue;
      if (rank.size() != 1) {
        report("conflicting highest-precedence port attribute on overlapping "
               "bits");
        return failure();
      }
      auto *source = &sources[*rank.begin()->second.begin()];
      if (!result.empty() && result.back().source == source &&
          result.back().low + result.back().width == it->first)
        result.back().width += next->first - it->first;
      else
        result.push_back({it->first, next->first - it->first, source});
      break;
    }
  }
  return result;
}
LogicalResult
PortAttributes::add(Delta &delta, const Key &key, StringRef name, Source source,
                    llvm::function_ref<void(const llvm::Twine &)> report) {
  if (!charge() || !source.width || source.low > UINT64_MAX - source.width ||
      source.precedence >= 8) {
    report("port attribute window or work limit exceeded");
    return failure();
  }
  auto [found, inserted] = delta[key].try_emplace(name.str());
  auto &sources = found->second;
  if (inserted)
    if (auto object = properties.find(key); object != properties.end())
      if (auto property = object->second.find(name.str());
          property != object->second.end()) {
        if (!charge(property->second.size())) {
          report("port attributes exceed 1048576 work units");
          return failure();
        }
        sources = property->second;
      }
  if (!charge(sources.size())) {
    report("port attributes exceed 1048576 work units");
    return failure();
  }
  if (!llvm::any_of(sources, [&](const Source &old) {
        return old.value == source.value &&
               old.precedence == source.precedence && old.low == source.low &&
               old.width == source.width && old.scope == source.scope &&
               old.top == source.top;
      }))
    sources.push_back(std::move(source));
  return succeeded(resolve(sources, report)) ? success() : failure();
}
void PortAttributes::commit(Delta &&delta) {
  for (auto &[key, values] : delta)
    for (auto &[name, sources] : values)
      properties[key][name] = std::move(sources);
}
LogicalResult PortAttributes::initialize() {
  module.walk([&](slangir::DefinitionSymbolOp definition) {
    if (auto path = definition.getHierarchicalName())
      models.emplace(path->str(), definition.getName()->str());
  });
  module.walk([&](slangir::PortSymbolOp declaration) {
    auto instance = declaration->getParentOfType<slangir::InstanceSymbolOp>();
    auto model = instance
                     ? instance->getAttrOfType<StringAttr>("referenced_path")
                     : StringAttr{};
    auto name = declaration->getAttrOfType<StringAttr>("name");
    auto path = declaration->getAttrOfType<StringAttr>("hierarchical_name");
    if (!model || !name || !path || name.getValue().empty())
      return;
    bool active = queries.isPort(path);
    Key key{active ? std::string{} : model.str(),
            active ? path.str() : name.str()};
    auto direction = declaration->getAttrOfType<IntegerAttr>("direction");
    auto type = declaration->getAttrOfType<TypeAttr>("semantic_type");
    auto reference = ControlReference::create(
        path, type ? type.getValue() : Type{},
        declaration->getAttrOfType<ArrayAttr>("declared_selection_types"),
        declaration->getAttrOfType<DenseBoolArrayAttr>(
            "declared_selection_signedness"),
        [](const llvm::Twine &) {});
    uint64_t width = succeeded(reference) ? reference->sourceWidth : 0;
    if (!direction || direction.getInt() < 0 || direction.getInt() > 2)
      width = 0;
    auto owner = active ? queries.parent(path) : model.str();
    if (ports
            .emplace(key, Port{key, owner, encodedDeclarationName(name),
                               model.str(), declaration, width,
                               direction ? direction.getInt() : -1})
            .second)
      modelPorts[model.str()].push_back(key);
  });
  Delta delta;
  for (const auto &[key, port] : ports) {
    for (Operation *owner :
         {port.declaration, key.model.empty() && objects.count(key.path)
                                ? objects.at(key.path)
                                : nullptr}) {
      if (!owner)
        continue;
      auto values =
          owner->getAttrOfType<DictionaryAttr>("hdl_power_attributes");
      if (!values)
        continue;
      for (auto property : values) {
        StringRef name = property.getName().getValue();
        if (name == "UPF_driver_supply" || name == "UPF_receiver_supply")
          return owner->emitError(
              "HDL port attributes are model-based; driver/receiver supplies "
              "require instance-based set_port_attributes (IEEE 1801-2018 "
              "Table 5)");
        if (!upf::isValidPortAttributeValue(name, property.getValue()))
          return owner->emitError("invalid or unsupported HDL port attribute: ")
                 << name;
        if (failed(add(delta, key, name,
                       {property.getValue(), owner->getLoc(), 3, 0,
                        port.width ? port.width : 1, port.owner, port.owner},
                       [&](const llvm::Twine &message) {
                         owner->emitError(message);
                       })))
          return failure();
      }
    }
  }
  commit(std::move(delta));
  return success();
}
LogicalResult PortAttributes::prepareDesign(
    StringRef path, DictionaryAttr values, StringRef scope, StringRef top,
    Location location, Delta &delta,
    llvm::function_ref<void(const llvm::Twine &)> report) {
  Key key{{}, path.str()};
  auto found = ports.find(key);
  if (found == ports.end()) {
    report("design attribute references an unsupported port representation");
    return failure();
  }
  for (auto property : values)
    if (failed(add(delta, key, property.getName(),
                   {property.getValue(), location, 6, 0,
                    found->second.width ? found->second.width : 1, scope.str(),
                    top.str()},
                   report)))
      return failure();
  return success();
}
int PortAttributes::set(
    Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[], StringRef scope,
    StringRef top, Location location, DesignAttributes &attributes,
    llvm::function_ref<FailureOr<std::string>(StringRef)> resolveSupply) {
  auto fail = [&](const llvm::Twine &message) {
    return portError(interp, message);
  };
  auto report = [&](const llvm::Twine &message) { fail(message); };
  if (objc < 2)
    return fail("set_port_attributes requires at least one argument");
  if (scope.empty() || top.empty())
    return fail("UPF requires a unique elaborated design top");
  std::map<std::string, Tcl_Obj *> options;
  NamedAttrList assigned;
  llvm::StringMap<Attribute> names;
  auto assign = [&](StringRef name, StringRef value) {
    if (name.empty() || name.contains('\0') || name.size() > 65536 ||
        value.size() > 65536 || !charge(1 + name.size() + value.size()))
      return fail("port attribute name/value or 1048576 work limit exceeded");
    if (upf::isPortAttributeName(name) && name != "UPF_driver_supply" &&
        name != "UPF_receiver_supply")
      return fail("port attribute consumer is not implemented: " + name);
    Attribute proposed = StringAttr::get(module->getContext(), value);
    if (!upf::isValidPortAttributeValue(name, proposed))
      return fail("invalid port attribute value or target: " + name);
    if (name == "UPF_driver_supply" || name == "UPF_receiver_supply") {
      auto resolved = resolveSupply(value);
      if (failed(resolved))
        return TCL_ERROR;
      proposed = StringAttr::get(module->getContext(), *resolved);
    }
    auto [old, inserted] = names.try_emplace(name, proposed);
    if (!inserted)
      return old->second == proposed
                 ? TCL_OK
                 : fail("conflicting values for port attribute " + name);
    assigned.append(name, proposed);
    return TCL_OK;
  };
  for (Tcl_Size i = 1; i < objc; ++i) {
    StringRef option = text(objv[i]);
    if (option == "-attribute") {
      if (++i == objc)
        return fail("missing value for -attribute");
      Tcl_Size count;
      Tcl_Obj **fields;
      if (Tcl_ListObjGetElements(interp, objv[i], &count, &fields) != TCL_OK)
        return TCL_ERROR;
      if (count != 2)
        return fail("port attribute requires {name value}");
      if (assign(text(fields[0]), text(fields[1])) != TCL_OK)
        return TCL_ERROR;
      continue;
    }
    if (!llvm::is_contained(
            ArrayRef<StringRef>{"-model", "-elements", "-exclude_elements",
                                "-ports", "-exclude_ports", "-applies_to",
                                "-driver_supply", "-receiver_supply"},
            option))
      return fail("unsupported set_port_attributes option: " + option);
    if (++i == objc)
      return fail("missing value for " + option);
    if (!options.emplace(option.str(), objv[i]).second)
      return fail("duplicate UPF option " + option);
    if (option == "-driver_supply" || option == "-receiver_supply")
      if (assign(("UPF_" + option.drop_front()).str(), text(objv[i])) != TCL_OK)
        return TCL_ERROR;
  }
  bool byModel = options.count("-model");
  if (options.count("-elements") && (byModel || options.count("-ports")))
    return fail("-elements cannot be combined with -model or -ports");
  if (byModel && options.count("-exclude_elements"))
    return fail("model-based instance exclusions are not implemented");
  auto list = [&](StringRef option, SmallVectorImpl<std::string> &out) {
    if (!options.count(option.str()))
      return TCL_OK;
    Tcl_Size count;
    Tcl_Obj **fields;
    if (Tcl_ListObjGetElements(interp, options.at(option.str()), &count,
                               &fields) != TCL_OK)
      return TCL_ERROR;
    if (count > 4096 || !charge(count))
      return fail(
          "port attribute selection exceeds 4096 entries or work limit");
    for (Tcl_Size i = 0; i < count; ++i)
      out.push_back(text(fields[i]).str());
    return TCL_OK;
  };
  SmallVector<std::string> elements, selected, excludedElements, excludedPorts,
      directions;
  if (list("-elements", elements) != TCL_OK ||
      list("-ports", selected) != TCL_OK ||
      list("-exclude_elements", excludedElements) != TCL_OK ||
      list("-exclude_ports", excludedPorts) != TCL_OK ||
      list("-applies_to", directions) != TCL_OK)
    return TCL_ERROR;
  bool supply =
      names.count("UPF_driver_supply") || names.count("UPF_receiver_supply");
  if (supply &&
      (byModel ||
       (!options.count("-ports") &&
        (!options.count("-elements") || elements.empty() ||
         !llvm::all_of(elements,
                       [](StringRef name) { return name == "."; }))) ||
       !llvm::all_of(selected,
                     [](StringRef name) { return simpleName(name); })))
    return fail("driver/receiver supplies require -elements {.} or local "
                "simple -ports (IEEE 1801-2018 Table 5)");
  std::set<int64_t> allowed;
  for (const auto &direction : directions) {
    int64_t value = direction == "inputs"    ? 0
                    : direction == "outputs" ? 1
                    : direction == "inouts"  ? 2
                                             : -1;
    if (value < 0)
      return fail("invalid port direction: " + direction);
    allowed.insert(value);
  }
  std::string model;
  bool localModel = false;
  if (byModel) {
    StringRef requested = text(options.at("-model"));
    if (requested == ".") {
      auto current = objects.find(attributes.instance(scope));
      auto reference =
          current == objects.end()
              ? StringAttr{}
              : current->second->getAttrOfType<StringAttr>("referenced_path");
      if (reference)
        model = reference.str();
    } else if (models.count(requested.str()))
      model = requested.str();
    else
      for (const auto &[id, name] : models)
        if (name == requested) {
          if (!model.empty())
            return fail("ambiguous port attribute model: " + requested);
          model = id;
        }
    if (model.empty())
      return fail("unknown port attribute model: " + requested);
    auto current = objects.find(scope.str());
    localModel =
        current != objects.end() &&
        current->second->getName().getStringRef() == "slang.symbol.instance" &&
        current->second->getAttrOfType<StringAttr>("referenced_path") ==
            StringAttr::get(module->getContext(), model);
  }
  struct Window {
    Key key;
    uint64_t low, width;
    bool part;
  };
  SmallVector<Window> candidates, excludes;
  SmallVector<DesignAttributes::Reference> references;
  auto access = [&](StringRef path) {
    if (!attributes.boundary(path, top, false, localModel).empty()) {
      fail("port attribute reference crosses macro terminal boundary: " + path);
      return false;
    }
    references.push_back(
        {path.str(), scope.str(), top.str(), location, false, localModel});
    return true;
  };
  auto addPort = [&](const Port &port, StringRef suffix,
                     SmallVectorImpl<Window> &out) {
    if (!charge()) {
      fail("port attributes exceed 1048576 work units");
      return false;
    }
    if (port.direction < 0 || port.direction > 2) {
      fail("unsupported interface/ref/composite port direction");
      return false;
    }
    if (port.key.model.empty()) {
      if (byModel && !localModel &&
          (!upf::isWithinPath(port.owner, top) ||
           attributes.insideLeaf(port.owner, top, true)))
        return true;
      if (!access(port.key.path))
        return false;
    }
    uint64_t low = 0, width = port.width ? port.width : 1;
    if (!suffix.empty()) {
      auto type = port.declaration->getAttrOfType<TypeAttr>("semantic_type");
      auto reference = ControlReference::create(
          port.key.path, type ? type.getValue() : Type{},
          port.declaration->getAttrOfType<ArrayAttr>(
              "declared_selection_types"),
          port.declaration->getAttrOfType<DenseBoolArrayAttr>(
              "declared_selection_signedness"),
          report);
      if (failed(reference) || failed(reference->select(suffix, report)))
        return false;
      low = reference->offset;
      width = reference->width;
    }
    out.push_back({port.key, low, width, !suffix.empty()});
    return true;
  };
  auto portSelector = [&](StringRef spelling, SmallVectorImpl<Window> &out) {
    size_t cut = spelling.size();
    while (true) {
      StringRef prefix = spelling.take_front(cut).rtrim();
      if (byModel) {
        if (simpleName(prefix)) {
          auto name = normalizedRequestName(prefix);
          SmallVector<const Port *> matches;
          for (const auto &key : modelPorts[model]) {
            if (!charge()) {
              fail("port attributes exceed 1048576 work units");
              return false;
            }
            if (ports.at(key).name == name)
              matches.push_back(&ports.at(key));
          }
          if (!matches.empty()) {
            for (auto *port : matches)
              if (!addPort(*port, spelling.drop_front(cut), out))
                return false;
            return true;
          }
        }
      } else {
        auto path = queries.resolve(prefix, scope, top);
        auto found = ports.find(Key{{}, path});
        if (found != ports.end())
          return addPort(found->second, spelling.drop_front(cut), out);
      }
      if (!cut)
        break;
      cut = spelling.rfind('[', cut - 1);
      if (cut == StringRef::npos)
        break;
    }
    fail("unknown or unsupported port attribute port: " + spelling);
    return false;
  };
  std::set<std::string> owners, excludedOwners;
  auto instanceSelector = [&](StringRef spelling, bool inclusion,
                              std::set<std::string> &out) {
    std::string path = inclusion && spelling == "."
                           ? top.str()
                           : queries.resolve(spelling, scope, top);
    auto found = objects.find(path);
    if (found == objects.end() ||
        found->second->getName().getStringRef() != "slang.symbol.instance") {
      fail("port attribute element is not a design instance: " + spelling);
      return false;
    }
    if (!access(path))
      return false;
    out.insert(path);
    return true;
  };
  for (const auto &name : elements)
    if (!instanceSelector(name, true, owners))
      return TCL_ERROR;
  for (const auto &name : excludedElements)
    if (!instanceSelector(name, false, excludedOwners))
      return TCL_ERROR;
  if (byModel && !options.count("-ports")) {
    for (const auto &key : modelPorts[model])
      if (!addPort(ports.at(key), {}, candidates))
        return TCL_ERROR;
  } else if (options.count("-ports")) {
    for (const auto &name : selected)
      if (!portSelector(name, candidates))
        return TCL_ERROR;
  } else if (options.count("-elements")) {
    for (const auto &[key, port] : ports) {
      if (!charge())
        return fail("port attributes exceed 1048576 work units");
      if (key.model.empty() && owners.count(port.owner) &&
          !addPort(port, {}, candidates))
        return TCL_ERROR;
    }
  }
  for (const auto &name : excludedPorts)
    if (!portSelector(name, excludes))
      return TCL_ERROR;
  Delta delta;
  for (const auto &candidate : candidates) {
    const auto &port = ports.at(candidate.key);
    if (excludedOwners.count(port.owner) ||
        (options.count("-applies_to") && !allowed.count(port.direction)))
      continue;
    SmallVector<std::pair<uint64_t, uint64_t>> ranges{
        {candidate.low, candidate.low + candidate.width}};
    for (const auto &exclude : excludes) {
      if (!charge(ranges.size() + 1))
        return fail("port attributes exceed 1048576 work units");
      if (candidate.key < exclude.key || exclude.key < candidate.key)
        continue;
      SmallVector<std::pair<uint64_t, uint64_t>> next;
      for (auto [low, high] : ranges) {
        uint64_t end = exclude.low + exclude.width;
        if (exclude.low >= high || end <= low)
          next.push_back({low, high});
        else {
          if (exclude.low > low)
            next.push_back({low, exclude.low});
          if (end < high)
            next.push_back({end, high});
        }
      }
      ranges = std::move(next);
    }
    unsigned precedence =
        byModel
            ? (options.count("-ports") ? (candidate.part ? 3 : 2)
                                       : (options.count("-applies_to") ? 1 : 0))
            : (options.count("-ports")
                   ? (candidate.part ? 7 : 6)
                   : (options.count("-applies_to") ? 5 : 4));
    for (auto [low, high] : ranges)
      for (auto property : assigned) {
        if ((property.getName() == "UPF_retention" ||
             property.getName() == "UPF_simstate_behavior") &&
            (low != 0 || high != (port.width ? port.width : 1)))
          return fail(
              "partial port design-attribute consumers are not implemented");
        if (failed(add(delta, candidate.key, property.getName(),
                       {property.getValue(), location, precedence, low,
                        high - low, scope.str(), top.str()},
                       report)))
          return TCL_ERROR;
      }
  }
  for (auto &reference : references)
    if (!attributes.record(std::move(reference)))
      return fail(
          "port attribute reference journal exceeds 1048576 work units");
  commit(std::move(delta));
  Tcl_ResetResult(interp);
  return TCL_OK;
}
LogicalResult PortAttributes::emit(OpBuilder &builder) {
  if (exceeded)
    return module.emitError("port attribute processing exceeded 1048576 work "
                            "units; caught errors cannot discard provenance");
  for (const auto &[key, values] : properties) {
    const auto &port = ports.at(key);
    for (const auto &[name, sources] : values) {
      auto segments = resolve(sources, [&](const llvm::Twine &message) {
        emitError(port.declaration->getLoc(), message);
      });
      if (failed(segments))
        return failure();
      for (auto segment : *segments) {
        const auto &source = *segment.source;
        auto dictionary = builder.getDictionaryAttr(
            {builder.getNamedAttr(name, source.value)});
        auto supply = [&, propertyName = name](StringRef property) {
          return propertyName == property
                     ? FlatSymbolRefAttr::get(cast<StringAttr>(source.value))
                     : FlatSymbolRefAttr{};
        };
        upf::UPFPortAttributesOp::create(
            builder, source.location, key.path, port.width ? segment.low : 0,
            port.width ? segment.width : 0, port.width, dictionary,
            source.scope, source.top,
            key.model.empty() ? StringAttr{} : builder.getStringAttr(key.model),
            supply("UPF_driver_supply"), supply("UPF_receiver_supply"));
      }
    }
  }
  return success();
}
} // namespace talos
#endif
