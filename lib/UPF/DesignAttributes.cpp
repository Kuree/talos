#include "DesignAttributes.h"
#ifdef TALOS_ENABLE_UPF
#include "talos/Dialect/Slang/SlangOps.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSwitch.h"

using namespace mlir;
namespace talos {
namespace {
int error(Tcl_Interp *interp, const llvm::Twine &message) {
  Tcl_SetObjResult(interp, Tcl_NewStringObj(message.str().c_str(), -1));
  Tcl_SetErrorCode(interp, "TALOS", "UPF", nullptr);
  return TCL_ERROR;
}
StringRef spelling(Tcl_Obj *object) {
  Tcl_Size size;
  const char *data = Tcl_GetStringFromObj(object, &size);
  return StringRef(data, size);
}
Attribute highest(const DesignAttributes::Properties &properties,
                  StringRef name) {
  auto found = properties.find(name.str());
  if (found == properties.end())
    return {};
  const DesignAttributes::Source *best = nullptr;
  for (const auto &source : found->second)
    if (!best || source.precedence > best->precedence)
      best = &source;
  return best ? best->value : Attribute{};
}
} // namespace
DesignAttributes::DesignAttributes(
    ModuleOp module, const std::map<std::string, Operation *> &objects,
    const DesignQuery &queries)
    : module(module), objects(objects), queries(queries) {}
bool DesignAttributes::charge(size_t count) {
  if (count > 1048576 - work) {
    exceeded = true;
    return false;
  }
  work += count;
  return true;
}
bool DesignAttributes::isInstance(StringRef path) const {
  auto found = objects.find(path.str());
  return found != objects.end() &&
         isa<slangir::InstanceSymbolOp>(found->second);
}
std::string DesignAttributes::model(StringRef path) const {
  std::string current = path.str();
  while (!current.empty()) {
    if (auto found = instanceModels.find(current);
        found != instanceModels.end())
      return found->second;
    current = parent(current);
  }
  return {};
}
std::string DesignAttributes::parent(StringRef path) const {
  auto key = path.str();
  if (auto found = parents.find(key); found != parents.end())
    return found->second;
  return parents.emplace(std::move(key), queries.parent(path)).first->second;
}
Attribute DesignAttributes::get(StringRef path, StringRef property) const {
  auto found = properties.find(path.str());
  return found == properties.end() ? Attribute{}
                                   : highest(found->second, property);
}
DictionaryAttr DesignAttributes::get(StringRef path) const {
  NamedAttrList result;
  if (auto found = properties.find(path.str()); found != properties.end())
    for (const auto &[name, sources] : found->second)
      result.set(name, highest(found->second, name));
  return result.getDictionary(module->getContext());
}
bool DesignAttributes::hardMacro(StringRef path) const {
  auto value = dyn_cast_or_null<StringAttr>(get(path, "UPF_is_hard_macro"));
  return value && value.getValue() == "TRUE";
}
bool DesignAttributes::softMacro(StringRef path) const {
  auto value = dyn_cast_or_null<StringAttr>(get(path, "UPF_is_soft_macro"));
  return value && value.getValue() == "TRUE";
}
bool DesignAttributes::leaf(StringRef path) const {
  return hardMacro(path) || softMacro(path);
}
bool DesignAttributes::hasMacros() const {
  return llvm::any_of(instanceModels,
                      [&](const auto &entry) { return leaf(entry.first); });
}
bool DesignAttributes::insideLeaf(StringRef path, StringRef context,
                                  bool includeSelf, bool hardOnly) {
  auto key = std::tuple{path.str(), context.str(), includeSelf, hardOnly};
  if (auto found = leafCache.find(key); found != leafCache.end())
    return found->second;
  std::string current = includeSelf ? path.str() : parent(path);
  while (!current.empty() && current != context) {
    if (!charge())
      return false;
    if (hardOnly ? hardMacro(current) : leaf(current)) {
      leafCache[key] = true;
      return true;
    }
    current = parent(current);
  }
  leafCache[key] = false;
  return false;
}
std::string DesignAttributes::boundary(StringRef path, StringRef top,
                                       bool includeSelf, bool localModel) {
  std::string current = includeSelf ? path.str() : parent(path);
  std::string portOwner = queries.isPort(path) ? instance(path) : std::string{};
  while (!current.empty()) {
    if (!charge())
      return current;
    if (leaf(current) && !(localModel && !hardMacro(current)) &&
        !upf::isWithinPath(top, current) &&
        (includeSelf || current != portOwner))
      return current;
    current = parent(current);
  }
  return {};
}
bool DesignAttributes::record(Reference reference) {
  if (!charge())
    return false;
  references.push_back(std::move(reference));
  return true;
}
std::string DesignAttributes::instance(StringRef path) const {
  std::string current = path.str();
  while (!current.empty()) {
    if (isInstance(current))
      return current;
    current = parent(current);
  }
  return {};
}
LogicalResult DesignAttributes::seed(StringRef path, DictionaryAttr values,
                                     unsigned precedence, StringRef modelName,
                                     Location location, bool modelBased) {
  if (!values)
    return success();
  for (auto entry : values) {
    if (!charge())
      return emitError(location, "design attributes exceed 1048576 work units");
    StringRef name = entry.getName().getValue();
    if (upf::isPortAttributeName(name))
      continue;
    if (!modelBased && upf::isDesignAttributeModelOnly(name)) {
      if (name == "UPF_is_hard_macro" || name == "UPF_is_soft_macro")
        return emitError(location,
                         "UPF_is_hard_macro and UPF_is_soft_macro are "
                         "model-only attributes (IEEE 1801-2018 5.6)");
      return emitError(location)
             << name << " is a model-only attribute (IEEE 1801-2018 5.6)";
    }
    if (!upf::isValidDesignAttributeValue(name, entry.getValue())) {
      if (name == "UPF_retention")
        return emitError(location,
                         "UPF_retention must be required or optional");
      return emitError(location)
             << "invalid value for design attribute " << name;
    }
    properties[path.str()][name.str()].push_back(
        {entry.getValue(), location, precedence, modelName.str(), {}, {}});
  }
  return success();
}
LogicalResult DesignAttributes::initialize() {
  module.walk([&](slangir::DefinitionSymbolOp definition) {
    if (auto path = definition.getHierarchicalName())
      models.emplace(path->str(),
                     Model{definition, definition.getName()->str(), {}});
  });
  for (const auto &[path, object] : objects)
    if (isInstance(path))
      if (auto reference =
              object->getAttrOfType<StringAttr>("referenced_path")) {
        instanceModels[path] = reference.str();
        if (auto found = models.find(reference.str()); found != models.end()) {
          found->second.instances.push_back(path);
          if (failed(seed(
                  path,
                  found->second.declaration->getAttrOfType<DictionaryAttr>(
                      "hdl_power_attributes"),
                  0, reference, found->second.declaration->getLoc(), true)))
            return failure();
        }
      }
  for (const auto &[path, object] : objects) {
    if (failed(seed(
            path, object->getAttrOfType<DictionaryAttr>("hdl_power_attributes"),
            isInstance(path) ? 1 : 0, {}, object->getLoc(), false)))
      return failure();
    if (auto *process = queries.process(path))
      if (failed(seed(
              path,
              process->getAttrOfType<DictionaryAttr>("hdl_power_attributes"), 0,
              {}, process->getLoc(), false)))
        return failure();
    if (auto *body = queries.processBody(path))
      if (failed(seed(
              path, body->getAttrOfType<DictionaryAttr>("hdl_power_attributes"),
              0, {}, body->getLoc(), false)))
        return failure();
  }
  for (const auto &[path, attributes] : properties)
    for (const auto &[name, sources] : attributes) {
      unsigned rank = 0;
      for (const auto &source : sources)
        rank = std::max(rank, source.precedence);
      Attribute value;
      for (const auto &source : sources)
        if (source.precedence == rank) {
          if (value && value != source.value)
            return emitError(source.location)
                   << "conflicting highest-precedence HDL design attribute "
                   << name << " on " << path;
          value = source.value;
        }
    }
  return success();
}
int DesignAttributes::set(Tcl_Interp *interp, Tcl_Size objc,
                          Tcl_Obj *const objv[], StringRef scope, StringRef top,
                          Location location) {
  if (scope.empty() || top.empty())
    return error(interp, "UPF requires a unique elaborated design top");
  std::map<std::string, Tcl_Obj *> options;
  NamedAttrList assigned;
  llvm::StringMap<Attribute> assignedValues;
  auto assign = [&](StringRef name, StringRef value) {
    if (!charge(1 + name.size() + value.size()))
      return error(interp, "design attributes exceed 1048576 work units");
    if (name.empty() || name.size() > 65536 || value.size() > 65536 ||
        name.contains('\0'))
      return error(
          interp,
          "design attribute name/value exceeds limits or has an invalid name");
    auto proposed = StringAttr::get(module->getContext(), value);
    if (auto old = assignedValues.find(name); old != assignedValues.end())
      return old->second == proposed
                 ? TCL_OK
                 : error(interp,
                         "conflicting values for design attribute " + name);
    if (upf::isPortAttributeName(name))
      return error(interp,
                   "port attribute requires set_port_attributes: " + name);
    if (!upf::isValidDesignAttributeValue(name, proposed))
      return error(interp, "invalid value for design attribute " + name);
    assignedValues[name] = proposed;
    assigned.append(name, proposed);
    return TCL_OK;
  };
  for (Tcl_Size i = 1; i < objc; ++i) {
    StringRef option = spelling(objv[i]);
    if (option == "-attribute") {
      if (++i == objc)
        return error(interp, "missing value for -attribute");
      Tcl_Size count;
      Tcl_Obj **fields;
      if (Tcl_ListObjGetElements(interp, objv[i], &count, &fields) != TCL_OK)
        return TCL_ERROR;
      if (count != 2)
        return error(interp, "design attribute requires {name value}");
      if (assign(spelling(fields[0]), spelling(fields[1])) != TCL_OK)
        return TCL_ERROR;
    } else if (option == "-is_soft_macro" || option == "-is_hard_macro" ||
               option == "-is_power_aware_model") {
      if (!options.emplace(option.str(), objv[i]).second)
        return error(interp, "duplicate UPF option " + option);
      int flag = true;
      if (i + 1 < objc && !spelling(objv[i + 1]).starts_with('-'))
        if (Tcl_GetBooleanFromObj(interp, objv[++i], &flag) != TCL_OK)
          return TCL_ERROR;
      if (assign(("UPF_" + option.drop_front()).str(),
                 flag ? "TRUE" : "FALSE") != TCL_OK)
        return TCL_ERROR;
    } else if (option == "-switch_cell_type") {
      if (!options.emplace(option.str(), objv[i]).second)
        return error(interp, "duplicate UPF option " + option);
      if (++i == objc)
        return error(interp, "missing value for -switch_cell_type");
      if (assign("UPF_switch_cell_type", spelling(objv[i])) != TCL_OK)
        return TCL_ERROR;
    } else {
      if (option != "-models" && option != "-elements" &&
          option != "-exclude_elements")
        return error(interp,
                     "unsupported set_design_attributes option: " + option);
      if (++i == objc)
        return error(interp, "missing value for " + option);
      if (!options.emplace(option.str(), objv[i]).second)
        return error(interp, "duplicate UPF option " + option);
    }
  }
  bool byModel = options.count("-models");
  if (byModel == bool(options.count("-elements")))
    return error(
        interp,
        "set_design_attributes requires exactly one of -models and -elements");
  if (options.count("-exclude_elements") && byModel)
    return error(interp, "-exclude_elements requires -elements");
  if (assigned.empty())
    return error(interp,
                 "set_design_attributes requires at least one attribute");
  for (auto entry : assigned)
    if (!byModel && upf::isDesignAttributeModelOnly(entry.getName()))
      return error(interp, "model-only design attribute requires -models: " +
                               entry.getName().getValue());
  auto list = [&](Tcl_Obj *value, SmallVectorImpl<std::string> &out) {
    Tcl_Size count;
    Tcl_Obj **fields;
    if (Tcl_ListObjGetElements(interp, value, &count, &fields) != TCL_OK)
      return TCL_ERROR;
    if (count > 4096)
      return error(interp, "design attribute selection exceeds 4096 elements");
    for (Tcl_Size i = 0; i < count; ++i)
      out.push_back(spelling(fields[i]).str());
    return TCL_OK;
  };
  SmallVector<std::string> names, exclusions;
  if (list(options.at(byModel ? "-models" : "-elements"), names) != TCL_OK ||
      (options.count("-exclude_elements") &&
       list(options.at("-exclude_elements"), exclusions) != TCL_OK))
    return TCL_ERROR;
  std::map<std::string, std::string> targets;
  SmallVector<std::string> excludedPaths;
  SmallVector<std::string> specifiedModels;
  auto object = [&](StringRef name, bool inclusion) {
    return inclusion && name == "." ? top.str()
                                    : queries.resolve(name, scope, top);
  };
  if (byModel) {
    for (const auto &name : names) {
      if (!charge(models.size() + 1))
        return error(interp, "design attributes exceed 1048576 work units");
      std::string id;
      if (name == ".")
        id = model(scope);
      else
        for (const auto &[path, candidate] : models)
          if (path == name || candidate.name == name) {
            if (!id.empty() && id != path)
              return error(interp, "ambiguous design model: " + name);
            id = path;
          }
      auto found = models.find(id);
      if (found == models.end())
        return error(interp, "unknown design model: " + name);
      specifiedModels.push_back(id);
      bool local = isInstance(scope) && model(scope) == id;
      for (const auto &path : found->second.instances) {
        if (!charge())
          return error(interp, "design attributes exceed 1048576 work units");
        if (local ? !boundary(path, top, false, true).empty()
                  : (!upf::isWithinPath(path, top) ||
                     insideLeaf(path, top, true)))
          continue;
        targets.emplace(path, id);
      }
    }
  } else {
    for (const auto &name : names) {
      auto path = object(name, true);
      if (!objects.count(path) ||
          (queries.isNamedBlock(path) && !queries.process(path)))
        return error(
            interp, "unknown or unsupported design attribute element: " + name);
      if (auto macro = boundary(path, top); !macro.empty())
        return error(
            interp,
            "design attribute reference crosses macro terminal boundary: " +
                macro);
      targets.emplace(path, std::string{});
    }
    for (const auto &name : exclusions) {
      auto path = object(name, false);
      if (!objects.count(path))
        return error(interp, "unknown design attribute exclusion: " + name);
      if (auto macro = boundary(path, top); !macro.empty())
        return error(
            interp,
            "design attribute exclusion crosses macro terminal boundary: " +
                macro);
      excludedPaths.push_back(path);
      targets.erase(path);
    }
  }
  if (exceeded)
    return error(interp, "design attributes exceed 1048576 work units");
  std::map<std::string, Properties> pending;
  for (const auto &[path, modelName] : targets) {
    if (!charge(assigned.getAttrs().size()))
      return error(interp, "design attributes exceed 1048576 work units");
    auto &next = pending[path];
    for (auto entry : assigned) {
      auto &sources = next[entry.getName().str()];
      auto original = properties.find(path);
      if (original != properties.end()) {
        auto property = original->second.find(entry.getName().str());
        if (property != original->second.end()) {
          if (!charge(property->second.size()))
            return error(interp, "design attributes exceed 1048576 work units");
          sources = property->second;
        }
      }
      if (!charge(sources.size()))
        return error(interp, "design attributes exceed 1048576 work units");
      unsigned proposedRank = byModel ? 0u : 1u;
      if (!llvm::any_of(sources,
                        [&, targetModel = modelName](const Source &source) {
                          return source.value == entry.getValue() &&
                                 source.precedence == proposedRank &&
                                 source.model == targetModel &&
                                 source.scope == scope && source.top == top;
                        }))
        sources.push_back({entry.getValue(), location, proposedRank, modelName,
                           scope.str(), top.str()});
      unsigned rank = 0;
      for (const auto &source : sources)
        rank = std::max(rank, source.precedence);
      Attribute value;
      for (const auto &source : sources)
        if (source.precedence == rank) {
          if (value && value != source.value)
            return error(interp,
                         "conflicting highest-precedence design attribute " +
                             entry.getName().getValue() + " on " + path);
          value = source.value;
        }
    }
  }
  auto leafAfter = [&](StringRef path) {
    auto changed = pending.find(path.str());
    auto value = [&](StringRef name) {
      auto attr = changed == pending.end() || !changed->second.count(name.str())
                      ? get(path, name)
                      : highest(changed->second, name);
      auto string = dyn_cast_or_null<StringAttr>(attr);
      return string && string.getValue() == "TRUE";
    };
    return value("UPF_is_hard_macro") || value("UPF_is_soft_macro");
  };
  auto hardAfter = [&](StringRef path) {
    auto changed = pending.find(path.str());
    auto value =
        changed == pending.end() || !changed->second.count("UPF_is_hard_macro")
            ? get(path, "UPF_is_hard_macro")
            : highest(changed->second, "UPF_is_hard_macro");
    auto string = dyn_cast_or_null<StringAttr>(value);
    return string && string.getValue() == "TRUE";
  };
  bool macroChange = llvm::any_of(pending, [&](const auto &entry) {
    return leafAfter(entry.first) != leaf(entry.first) ||
           hardAfter(entry.first) != hardMacro(entry.first);
  });
  if (macroChange)
    for (const auto &reference : references) {
      std::string current =
          reference.includeSelf ? reference.path : parent(reference.path);
      std::string portOwner = queries.isPort(reference.path)
                                  ? instance(reference.path)
                                  : std::string{};
      while (!current.empty()) {
        if (!charge())
          return error(interp, "design attributes exceed 1048576 work units");
        if (leafAfter(current) && !upf::isWithinPath(reference.top, current) &&
            !(reference.localModel && !hardAfter(current)) &&
            (reference.includeSelf || current != portOwner))
          return error(interp, "macro attribute invalidates an earlier "
                               "reference across its terminal boundary: " +
                                   reference.path + " from design top " +
                                   reference.top);
        current = parent(current);
      }
    }
  // Reserve journal work before committing this command's property edits.
  if (!charge(targets.size() + excludedPaths.size()))
    return error(interp, "design attributes exceed 1048576 work units");
  for (auto &[path, next] : pending)
    for (auto &[name, sources] : next)
      properties[path][name] = std::move(sources);
  if (macroChange)
    leafCache.clear();
  for (auto &model : specifiedModels)
    modelSpecifications.push_back({model, scope.str(), top.str(),
                                   assigned.getDictionary(module->getContext()),
                                   location});
  for (const auto &[path, targetModel] : targets)
    references.push_back(
        {path, scope.str(), top.str(), location, false,
         byModel && isInstance(scope) && model(scope) == targetModel});
  for (auto &path : excludedPaths)
    references.push_back(
        {std::move(path), scope.str(), top.str(), location, false});
  Tcl_ResetResult(interp);
  return TCL_OK;
}
LogicalResult DesignAttributes::emit(OpBuilder &builder) {
  if (exceeded)
    return module.emitError("design attribute processing exceeded 1048576 work "
                            "units; caught errors cannot discard provenance");
  auto emit = [&](Location location, upf::RetentionElementAttr element,
                  DictionaryAttr values) {
    upf::RetentionPurposeAttr retention;
    if (auto value = values.getAs<StringAttr>("UPF_retention"))
      retention = upf::RetentionPurposeAttr::get(
          module->getContext(),
          *upf::symbolizeRetentionPurpose(value.getValue()));
    auto boolean = [&](StringRef name) {
      auto value = values.getAs<StringAttr>(name);
      return value && value.getValue() == "TRUE";
    };
    upf::UPFDesignAttributesOp::create(
        builder, location, element, retention, boolean("UPF_is_hard_macro"),
        boolean("UPF_is_soft_macro"), values, StringAttr{}, StringAttr{});
  };
  for (const auto &[path, entries] : properties) {
    auto values = get(path);
    if (values.empty())
      continue;
    auto *object = objects.at(path);
    auto kind = queries.isScope(path)   ? upf::RetentionElementKind::Instance
                : queries.process(path) ? upf::RetentionElementKind::Process
                                        : upf::RetentionElementKind::Signal;
    emit(object->getLoc(),
         upf::RetentionElementAttr::get(module->getContext(),
                                        builder.getStringAttr(path), kind),
         values);
  }
  for (const auto &spec : modelSpecifications)
    upf::UPFModelAttributesOp::create(builder, spec.location, spec.model,
                                      spec.values, spec.scope, spec.top);
  return success();
}
} // namespace talos
#endif
