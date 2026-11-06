// Tcl executes the language; this file implements UPF commands and design
// lookup.
#include "BooleanExpression.h"
#include "ControlReference.h"
#include "DesignQuery.h"
#include "SupplyExpression.h"
#include "SupplyNetwork.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Verifier.h"
#include "talos/Dialect/Slang/SlangOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <variant>
#include <vector>
#ifdef TALOS_ENABLE_UPF
#include <tcl.h>
#endif
using namespace mlir;
using llvm::StringRef;
namespace talos {
#ifdef TALOS_ENABLE_UPF
namespace {
struct Retention {
  std::string name, scope, retentionSupply, primarySupply;
  std::map<std::string, Attribute> elements, excluded;
  bool hasElements = false, noRetention = false, useRetentionAsPrimary = false;
  std::optional<bool> retentionSupplyCorrupt, saveRestoreCorrupt;
  upf::RetentionTriggerAttr save, restore;
  upf::ExpressionAttr saveCondition, restoreCondition, condition;
  std::optional<Location> location;
  uint64_t sourceOrdinal = 0;
};
struct RetentionEdit {
  Retention intent;
  bool update = false;
  std::string supplier;
};
struct IsolationEdit {
  std::string name, scope, control;
  std::optional<Location> location;
  bool high = true, diffSupplyOnly = true;
  int64_t clamp = 0;
};
using StrategyEdit = std::variant<RetentionEdit, IsolationEdit>;
struct CompositeStrategyEdit {
  std::string domain;
  StrategyEdit edit;
  std::set<std::string> applied;
};
struct Domain {
  std::string name, scope, switchInput, switchOutput, isolation;
  std::string inputPort, outputPort;
  std::optional<SupplyObject> inputSupply, outputSupply;
  std::string primary;
  std::string isolationName;
  SmallVector<Attribute> on, partial, errors;
  upf::SwitchStateAttr off;
  std::vector<std::string> elements, excluded, subdomains;
  bool hasElements = false, hasExcluded = false, atomic = false, composite = false;
  bool isolationHigh = true;
  bool isolationDiffSupplyOnly = true;
  int64_t clamp = 0;
  bool primaryAssociated = false;
  std::optional<Location> location;
  std::map<std::string, Retention> retentions;
};
struct SupplySet {
  std::string scope;
  bool handle = false;
  std::map<std::string, SupplyObject> functions;
  std::set<std::string> required;
  std::optional<std::string> updateScope;
  std::optional<Location> location;
  struct State {
    std::optional<SupplyExpression> condition;
    std::optional<Location> location;
    upf::Simstate simstate = upf::Simstate::Unspecified;
    bool illegal = false;
  };
  std::map<std::string, State> states;
  std::optional<std::string> stateScope;
  bool complete = false;
  std::string owner;
  std::string strategy;
  std::string binding;
  bool explicitStrategySupply = false;
  bool privateSupplier = false;
};
struct DomainNet {
  std::string scope, owner, resolution;
  std::set<std::string> domains;
};
struct Session {
  ModuleOp module;
  Tcl_Interp *interp;
  bool allowHDLExpressions;
  DesignQuery queries;
  std::optional<upf::PartialOnTranslation> partialOnTranslation;
  std::string top, scope, file, designModule;
  std::map<std::string, Operation *> objects;
  std::map<std::string, Domain> domains;
  std::set<std::string> nets, supplyPorts, switches;
  // IEEE 1801-2018 6.24.1: ownership and -reuse availability belong to a
  // declared net, not the resolved electrical root shared with other objects.
  std::map<std::string, DomainNet> domainNets;
  SupplyPorts supplyPortInfo;
  SupplyBindings supplyBindings;
  std::map<std::string, SupplySet> supplySets;
  std::vector<std::pair<std::string, std::string>> setAssociations;
  std::vector<CompositeStrategyEdit> compositeStrategies;
  size_t compositeStrategyCost = 0;
  uint64_t strategyOrdinal = 0;
  std::set<std::string> declaredHDLNames;
  Session(ModuleOp module, Tcl_Interp *interp, bool allowHDLExpressions)
      : module(module), interp(interp),
        allowHDLExpressions(allowHDLExpressions), queries(module) {
    std::set<std::string> tops;
    module.walk([&](Operation *op) {
      for (Operation *owner = op; owner; owner = owner->getParentOp())
        if (auto inactive = owner->getAttrOfType<BoolAttr>("is_uninstantiated");
            inactive && inactive.getValue())
          return;
      auto path = op->getAttrOfType<StringAttr>("hierarchical_name");
      if (path)
        declaredHDLNames.insert(path.str());
      StringRef kind = op->getName().getStringRef();
      if (!path ||
          (kind != "slang.symbol.instance" && kind != "slang.symbol.generate_block" &&
           kind != "slang.symbol.variable" &&
           kind != "slang.symbol.net" && kind != "slang.symbol.port"))
        return;
      if (kind != "slang.symbol.port" || !objects.count(path.str()))
        objects[path.str()] = op;
      if (op->getName().getStringRef() == "slang.symbol.instance" &&
          queries.isTop(path)) {
        tops.insert(path.str());
      }
    });
    if (tops.size() == 1)
      top = *tops.begin();
    scope = top;
  }
  int error(const llvm::Twine &message) {
    Tcl_SetObjResult(interp, Tcl_NewStringObj(message.str().c_str(), -1));
    Tcl_SetErrorCode(interp, "TALOS", "UPF", nullptr);
    return TCL_ERROR;
  }
  std::string resolve(StringRef name) const {
    if (name == "." || name.empty())
      return scope;
    std::string result;
    if (name.starts_with('/'))
      result = top + "." + name.drop_front().str();
    else
      result = scope.empty() ? name.str() : scope + "." + name.str();
    for (char &ch : result)
      if (ch == '/')
        ch = '.';
    if (name == "/")
      result = top;
    return result;
  }
  // IEEE 1801-2018 5.3.3.4: '/' is relative to the current design-top instance.
  std::string rooted(StringRef path) const {
    return queries.rooted(path, top);
  }
  std::string model(StringRef instance) const {
    auto found = objects.find(instance.str());
    if (found != objects.end())
      if (auto name =
              found->second->getAttrOfType<StringAttr>("referenced_path"))
        return name.str();
    return {};
  }
  // IEEE 1801-2018 5.3.2 constrains UPF identifiers independently of Tcl
  // strings.
  bool identifier(StringRef name) {
    if (name.empty()) {
      error("UPF identifier must not be empty");
      return false;
    }
    const char *cursor = name.data(), *end = cursor + name.size();
    bool first = true;
    while (cursor < end) {
      Tcl_UniChar code;
      int count = Tcl_UtfToUniChar(cursor, &code);
      if (count <= 0 || count > end - cursor ||
          (first ? !Tcl_UniCharIsAlpha(code)
                 : !(Tcl_UniCharIsAlnum(code) || code == '_'))) {
        error("invalid UPF identifier: " + name);
        return false;
      }
      cursor += count;
      first = false;
    }
    return true;
  }
  Location declarationLocation() {
    // Preserve the UPF call site for later MLIR elaboration diagnostics,
    // including commands invoked through Tcl procedures and source libraries.
    Tcl_InterpState saved = Tcl_SaveInterpState(interp, TCL_OK);
    std::string path = file;
    int line = 1;
    if (Tcl_EvalEx(interp, "info frame -1", -1, TCL_EVAL_DIRECT) == TCL_OK) {
      Tcl_Obj *frame = Tcl_GetObjResult(interp);
      for (const char *field : {"file", "line"}) {
        Tcl_Obj *key = Tcl_NewStringObj(field, -1), *value = nullptr;
        Tcl_IncrRefCount(key);
        if (Tcl_DictObjGet(interp, frame, key, &value) == TCL_OK && value) {
          if (StringRef(field) == "file")
            path = Tcl_GetString(value);
          else
            (void)Tcl_GetIntFromObj(interp, value, &line);
        }
        Tcl_DecrRefCount(key);
      }
    }
    Tcl_RestoreInterpState(interp, saved);
    return FileLineColLoc::get(module.getContext(), path, std::max(1, line), 1);
  }
  std::string object(StringRef name) const {
    std::string result = queries.resolve(name, scope, top);
    if (objects.count(result))
      return result;
    // Preserve the existing dotted-HDL extension for unambiguous names.
    result = resolve(name);
    if (objects.count(result))
      return result;
    return {};
  }
  std::string key(StringRef name) const { return resolve(name); }
  bool creationScope(StringRef path) {
    auto found = objects.find(path.str());
    if (found != objects.end() &&
        found->second->getName().getStringRef() == "slang.symbol.generate_block") {
      error("cannot create UPF objects in a generate block (IEEE 1801-2018 clause 3)");
      return false;
    }
    return true;
  }
  std::string supplySetKey(StringRef name) const {
    // 5.3.3.3/.5: '/' separates HDL scopes; dots select UPF object fields.
    // Keeping those separators distinct also avoids a collision between
    // SS.power in this scope and the net power in an HDL instance named SS.
    size_t slash = name.rfind('/');
    StringRef local =
        slash == StringRef::npos ? name : name.drop_front(slash + 1);
    std::string owner =
        slash == StringRef::npos
            ? scope
            : resolve(slash == 0 ? StringRef("/") : name.take_front(slash));
    return (owner.empty() ? std::string{} : absoluteSupplyHandle(owner)) + "/" +
           local.str();
  }
  std::optional<SupplyObject> supply(StringRef name,
                                     bool allowPort = false) const {
    std::string path = key(name);
    size_t slash = name.rfind('/');
    StringRef local = name.drop_front(slash == StringRef::npos ? 0 : slash + 1);
    if (allowPort && !local.contains('.') && supplyPorts.count(path))
      return SupplyObject{SupplyObject::Port, path,
                          StringRef(path).rsplit('.').first.str()};
    if (nets.count(path) && !local.contains('.'))
      return SupplyObject{SupplyObject::Net, path,
                          StringRef(path).rsplit('.').first.str()};
    auto parts = name.rsplit('.');
    if (parts.first != name &&
        llvm::is_contained(upf::getSupplyFunctionNames(), parts.second)) {
      auto found = supplySets.find(supplySetKey(parts.first));
      if (found != supplySets.end())
        return SupplyObject{SupplyObject::Function,
                            found->first + "." + parts.second.str(),
                            found->second.scope};
    }
    return std::nullopt;
  }
  SupplyObject function(StringRef set, StringRef name) const {
    return {SupplyObject::Function, (set + "." + name).str(),
            supplySets.at(set.str()).scope};
  }
  bool sameSupply(const SupplyObject &a, const SupplyObject &b,
                  StringRef pendingName = {},
                  const SupplySet *pending = nullptr,
                  const SupplyBindings *pendingBindings = nullptr) const {
    if (a == b)
      return true;
    using Identity = std::pair<int, std::string>;
    auto identity = [](const SupplyObject &object) -> Identity {
      return {object.kind, object.path};
    };
    std::map<Identity, std::vector<SupplyObject>> graph;
    auto link = [&](SupplyObject x, SupplyObject y) {
      graph[identity(x)].push_back(y);
      graph[identity(y)].push_back(x);
    };
    auto add = [&](StringRef name, const SupplySet &set) {
      for (auto &[field, object] : set.functions)
        link({SupplyObject::Function, (name + "." + field).str(), set.scope},
             object);
    };
    for (auto &[name, set] : supplySets)
      add(name, pending && name == pendingName ? *pending : set);
    if (pending && !supplySets.count(pendingName.str()))
      add(pendingName, *pending);
    for (auto &[x, y] : setAssociations)
      for (StringRef field : upf::getSupplyFunctionNames())
        link(function(x, field), function(y, field));
    for (auto &[side, net] :
         pendingBindings ? *pendingBindings : supplyBindings)
      link({SupplyObject::Port, side.first,
            StringRef(side.first).rsplit('.').first.str()},
           net);
    std::vector<SupplyObject> work{a};
    std::set<Identity> seen;
    while (!work.empty()) {
      auto current = std::move(work.back());
      work.pop_back();
      if (current == b)
        return true;
      if (!seen.insert(identity(current)).second)
        continue;
      for (auto &next : graph[identity(current)])
        work.push_back(next);
    }
    return false;
  }
  bool hasNamedSet(StringRef name) const {
    return supplySets.count(supplySetKey(name));
  }
  bool hasNamedObject(StringRef name, bool allowSupplyPair = false) const {
    // IEEE 1801-2018 5.3.3.2/5.5: HDL declarations and UPF domains,
    // switches and supply objects share their creation scope's namespace.
    // 10.3.2.2.3 permits a supply port/net pair with the same simple name;
    // the caller still rejects a second declaration of its own class.
    // Strategies live inside a domain instead (10.6.1.1), so they are not
    // peers of objects in the surrounding HDL scope.
    std::string path = key(name);
    return hasNamedSet(name) || declaredHDLNames.count(path) ||
           domains.count(path) || switches.count(path) ||
           (!allowSupplyPair && (nets.count(path) || supplyPorts.count(path)));
  }
  bool functionSupply(const SupplyObject &object) {
    // IEEE 1801-2018 6.24.1/6.26/6.43: a net created with -domain cannot
    // be associated with any supply-set function, including legacy primary
    // associations. Check the ORIGINAL operand before an equivalent existing
    // binding can make the update idempotent. Ports and functions keep their
    // own identities (4.3.8/6.14/10.6.1.6); electrical equivalence does not
    // transfer a distinct net declaration's ownership restriction to them.
    if (object.kind == SupplyObject::Net && domainNets.count(object.path)) {
      error("a supply net created with -domain cannot be associated with a "
            "supply-set function (IEEE 1801-2018 6.24.1): " +
            object.path);
      return false;
    }
    // 6.26.1: concrete supplies must be local; descendant references are
    // permitted through supply-net handles, not concrete net names. 6.43's
    // equivalent caller-scoped supply-set declaration obeys the same rules.
    bool descendant = StringRef(object.scope).starts_with(scope + ".");
    if (object.scope != scope && object.kind != SupplyObject::Function) {
      error("supply function requires a net or port defined in the current "
            "scope (IEEE 1801-2018 6.26)");
      return false;
    }
    if (object.scope != scope && !descendant) {
      error("function handles declared outside the current scope or its "
            "descendants are not implemented");
      return false;
    }
    return true;
  }
  void markPrimaryAssociations(std::set<std::string> sets) {
    // Whole-set associations propagate to functions connected later (6.10).
    bool changed;
    do {
      changed = false;
      for (auto &[a, b] : setAssociations)
        if (sets.count(a) || sets.count(b)) {
          changed |= sets.insert(a).second;
          changed |= sets.insert(b).second;
        }
    } while (changed);
    for (auto &[name, domain] : domains)
      if (sets.count(domain.primary))
        domain.primaryAssociated = true;
  }
  bool list(Tcl_Obj *obj, std::vector<std::string> &out) {
    Tcl_Size count;
    Tcl_Obj **items;
    if (Tcl_ListObjGetElements(interp, obj, &count, &items) != TCL_OK)
      return false;
    for (Tcl_Size i = 0; i < count; ++i)
      out.emplace_back(Tcl_GetString(items[i]));
    return true;
  }
  using Options = std::map<std::string, Tcl_Obj *>;
  using RepeatedOptions = std::map<std::string, std::vector<Tcl_Obj *>>;
  bool options(Tcl_Size objc, Tcl_Obj *const objv[], Tcl_Size first,
               std::initializer_list<StringRef> allowed, Options &out,
               RepeatedOptions *repeated = nullptr,
               std::initializer_list<StringRef> flags = {}) {
    for (Tcl_Size i = first; i < objc; ++i) {
      StringRef option = Tcl_GetString(objv[i]);
      if (!llvm::is_contained(allowed, option)) {
        error("unsupported UPF option '" + option + "' in " +
              Tcl_GetString(objv[0]));
        return false;
      }
      if (llvm::is_contained(flags, option)) {
        if (!out.emplace(option.str(), objv[i]).second) {
          error("duplicate UPF option " + option);
          return false;
        }
        continue;
      }
      if (++i == objc) {
        error("missing value for " + option);
        return false;
      }
      if (repeated)
        if (auto found = repeated->find(option.str());
            found != repeated->end()) {
          found->second.push_back(objv[i]);
          continue;
        }
      if (!out.emplace(option.str(), objv[i]).second) {
        error("duplicate UPF option " + option);
        return false;
      }
    }
    return true;
  }
  static StringRef value(const Options &options, StringRef key) {
    auto found = options.find(key.str());
    return found == options.end() ? StringRef{}
                                  : StringRef(Tcl_GetString(found->second));
  }
  Domain *domain(const Options &options, bool allowComposite = false) {
    auto found = domains.find(key(value(options, "-domain")));
    if (found == domains.end()) {
      error("unknown power domain '" + value(options, "-domain") + "'");
      return nullptr;
    }
    if (found->second.composite && !allowComposite) {
      error("this command on a composite domain is not implemented");
      return nullptr;
    }
    return &found->second;
  }
  bool control(StringRef path, std::string &out, bool *isSigned = nullptr) {
    out = object(path);
    if (out.empty()) {
      error("design object not found: " + path);
      return false;
    }
    Operation *op = objects.at(out);
    auto type = op->getAttrOfType<TypeAttr>("semantic_type");
    Type scalar = type ? type.getValue() : Type{};
    // IEEE 1801-2018 6.22: a one-bit HDL control can also be written as a
    // packed array with singleton dimensions (for example, logic [0:0]).
    while (auto array = dyn_cast_or_null<slangir::PackedArrayType>(scalar)) {
      if (array.getLeft() != array.getRight())
        break;
      scalar = array.getElementType();
    }
    auto integral = dyn_cast_or_null<slangir::IntegralType>(scalar);
    if (!integral || integral.getWidth() != 1) {
      error("UPF control requires a one-bit integral design object: " + path);
      return false;
    }
    if (isSigned)
      *isSigned = integral.getIsSigned();
    return true;
  }
  FailureOr<ControlReference>
  reference(StringRef name,
            const std::map<std::string, ControlReference> *aliases = nullptr) {
    // Match the longest real object first: brackets can belong to an instance
    // array/generate name, rather than to the final HDL signal selection.
    size_t cut = name.size();
    while (true) {
      StringRef prefix = name.take_front(cut).rtrim();
      std::optional<ControlReference> resolved;
      if (aliases) {
        auto found = aliases->find(prefix.str());
        if (found != aliases->end())
          resolved = found->second;
      }
      auto report = [&](const llvm::Twine &message) { error(message); };
      if (!resolved) {
        std::string path = object(prefix);
        if (!path.empty()) {
          auto type =
              objects.at(path)->getAttrOfType<TypeAttr>("semantic_type");
          auto result = ControlReference::create(
              path, type ? type.getValue() : Type{},
              objects.at(path)->getAttrOfType<ArrayAttr>(
                  "declared_selection_types"),
              objects.at(path)->getAttrOfType<DenseBoolArrayAttr>(
                  "declared_selection_signedness"),
              report);
          if (failed(result))
            return failure();
          resolved = *result;
        }
      }
      if (resolved) {
        if (failed(resolved->select(name.drop_front(cut), report)))
          return failure();
        return *resolved;
      }
      if (!cut)
        break;
      cut = name.rfind('[', cut - 1);
      if (cut == StringRef::npos)
        break;
    }
    error("design object not found: " + name);
    return failure();
  }
  bool strategyBinding(StringRef handle, StringRef supplier) {
    // IEEE 1801-2018 6.10 limits a strategy's explicit -handle binding to
    // one supply set. General list-form electrical associations remain valid.
    auto found = supplySets.find(handle.str());
    if (found != supplySets.end() && !found->second.strategy.empty() &&
        !found->second.binding.empty() && found->second.binding != supplier) {
      error(
          "strategy supply handle cannot associate more than one supply set: " +
          handle);
      return false;
    }
    return true;
  }
  int applyStrategy(Domain &dom, const RetentionEdit &edit,
                    bool pendingSuppliers = false) {
    const auto &delta = edit.intent;
    auto found = dom.retentions.find(delta.name);
    if (found != dom.retentions.end() && !edit.update)
      return error("retention strategy already exists; use -update");
    if (found == dom.retentions.end() && edit.update)
      return error("cannot update an unknown retention strategy");
    if (edit.update && found->second.sourceOrdinal >= delta.sourceOrdinal)
      return error(
          "cannot update a retention strategy before its base declaration");
    Retention next;
    if (found != dom.retentions.end()) {
      next = found->second;
      if (next.scope != delta.scope)
        return error("retention update must execute in the original scope");
    } else {
      if (dom.retentions.size() >= 256)
        return error("power domain exceeds 256 retention strategies");
      next.name = delta.name;
      next.scope = delta.scope;
      next.location = delta.location;
      next.sourceOrdinal = delta.sourceOrdinal;
      std::string stem =
          StringRef(dom.primary).drop_back(8).str() + "." + delta.name;
      if (supplySets.count(stem) || dom.isolationName == delta.name)
        return error("retention strategy name conflicts with another object in "
                     "the domain");
      next.retentionSupply = stem + ".retention_supply";
      next.primarySupply = stem + ".primary_supply";
      if (supplySets.count(next.retentionSupply) ||
          supplySets.count(next.primarySupply))
        return error("retention strategy supply handle already exists");
    }
    next.elements.insert(delta.elements.begin(), delta.elements.end());
    next.excluded.insert(delta.excluded.begin(), delta.excluded.end());
    if (next.elements.size() > 4096 || next.excluded.size() > 4096)
      return error("retention selection exceeds 4096 elements");
    next.hasElements |= delta.hasElements;
    next.noRetention |= delta.noRetention;
    next.useRetentionAsPrimary |= delta.useRetentionAsPrimary;
    auto refine = [&](auto &target, auto proposed, StringRef description) {
      if (target && proposed && target != proposed) {
        error("conflicting or unsupported retention " + description +
              " refinement");
        return false;
      }
      if (proposed)
        target = proposed;
      return true;
    };
    if (!refine(next.save, delta.save, "trigger") ||
        !refine(next.restore, delta.restore, "trigger") ||
        !refine(next.saveCondition, delta.saveCondition, "condition") ||
        !refine(next.restoreCondition, delta.restoreCondition, "condition") ||
        !refine(next.condition, delta.condition, "condition") ||
        !refine(next.retentionSupplyCorrupt, delta.retentionSupplyCorrupt,
                "corruption parameter") ||
        !refine(next.saveRestoreCorrupt, delta.saveRestoreCorrupt,
                "corruption parameter"))
      return TCL_ERROR;
    size_t tokens = 0;
    auto count = [&](const Retention &retention) {
      for (auto expression : {retention.saveCondition,
                              retention.restoreCondition, retention.condition})
        if (expression)
          tokens += expression.getTokens().size();
    };
    for (auto &[name, retention] : dom.retentions)
      if (name != delta.name)
        count(retention);
    count(next);
    if (tokens > 65536)
      return error("power domain exceeds 65536 retention expression tokens");
    std::map<std::string, SupplySet> handles;
    SmallVector<std::pair<std::string, std::string>> links;
    if (found == dom.retentions.end()) {
      for (auto &id : {next.retentionSupply, next.primarySupply}) {
        SupplySet handle;
        // 10.6.1.2: strategy identity is in the physical domain's HDL scope;
        // 5.10/8.3.2: updates still use the command's original execution scope.
        handle.scope = dom.scope;
        handle.updateScope = delta.scope;
        handle.handle = true;
        handle.location = delta.location;
        handle.owner = dom.name;
        handle.strategy = delta.name;
        handle.required = {"power", "ground"};
        handles.emplace(id, std::move(handle));
      }
      handles.at(next.primarySupply).binding = dom.primary;
      links.emplace_back(next.primarySupply, dom.primary);
    }
    if (!edit.supplier.empty()) {
      if (edit.supplier == next.retentionSupply)
        return error(
            "retention supply cannot refer to its own predefined handle");
      if (!pendingSuppliers && !supplySets.count(edit.supplier) &&
          !handles.count(edit.supplier))
        return error("unknown retention supply set: " + edit.supplier);
      if (!strategyBinding(next.retentionSupply, edit.supplier))
        return TCL_ERROR;
      links.emplace_back(next.retentionSupply, edit.supplier);
    }
    // A failed leaf leaves its own declaration intact. Composite callers wrap
    // all leaves and the provenance record in a single compiler transaction.
    supplySets.insert(handles.begin(), handles.end());
    if (!edit.supplier.empty()) {
      auto &handle = supplySets.at(next.retentionSupply);
      handle.binding = edit.supplier;
      handle.explicitStrategySupply = true;
    }
    setAssociations.insert(setAssociations.end(), links.begin(), links.end());
    dom.retentions.insert_or_assign(delta.name, std::move(next));
    return TCL_OK;
  }
  int applyStrategy(Domain &dom, const IsolationEdit &edit,
                    bool pendingSuppliers = false) {
    std::string path =
        StringRef(dom.primary).drop_back(8).str() + "." + edit.name;
    if (dom.retentions.count(edit.name) || supplySets.count(path))
      return error("isolation strategy name conflicts with another object in "
                   "the domain");
    if (!dom.isolation.empty())
      return error("one isolation strategy per domain is supported");
    dom.isolation = edit.control;
    dom.isolationName = edit.name;
    dom.isolationHigh = edit.high;
    dom.clamp = edit.clamp;
    dom.isolationDiffSupplyOnly = edit.diffSupplyOnly;
    return TCL_OK;
  }
  int applyStrategy(Domain &dom, const StrategyEdit &edit,
                    bool pendingSuppliers = false) {
    return std::visit(
        [&](const auto &delta) {
          return applyStrategy(dom, delta, pendingSuppliers);
        },
        edit);
  }
  int validateStrategySupplier(const StrategyEdit &edit) {
    if (auto retention = std::get_if<RetentionEdit>(&edit);
        retention && !retention->supplier.empty() &&
        !supplySets.count(retention->supplier))
      return error("unknown retention supply set: " + retention->supplier);
    return TCL_OK;
  }
  std::set<std::string> physicalLeaves(StringRef name) const {
    std::set<std::string> leaves, seen;
    std::vector<std::string> work{name.str()};
    while (!work.empty()) {
      std::string current = std::move(work.back());
      work.pop_back();
      if (!seen.insert(current).second)
        continue;
      const auto &dom = domains.at(current);
      if (!dom.composite)
        leaves.insert(current);
      else
        work.insert(work.end(), dom.subdomains.begin(), dom.subdomains.end());
    }
    return leaves;
  }
  int strategyTransaction(llvm::function_ref<int()> action) {
    auto oldDomains = domains;
    auto oldSets = supplySets;
    auto oldLinks = setAssociations;
    size_t oldCount = compositeStrategies.size();
    size_t oldCost = compositeStrategyCost;
    int result = action();
    if (result != TCL_OK) {
      domains = std::move(oldDomains);
      supplySets = std::move(oldSets);
      setAssociations = std::move(oldLinks);
      compositeStrategies.resize(oldCount);
      compositeStrategyCost = oldCost;
    }
    return result;
  }
  int distributeStrategy(const std::string &target, StrategyEdit edit) {
    if (!domains.at(target).composite) {
      int result = applyStrategy(domains.at(target), edit);
      if (result == TCL_OK)
        Tcl_ResetResult(interp);
      return result;
    }
    // Empty containers still retain deltas for future members. Bound that
    // compiler inventory independently of per-leaf strategy/expression limits.
    size_t cost = 1;
    if (auto retention = std::get_if<RetentionEdit>(&edit)) {
      cost +=
          retention->intent.elements.size() + retention->intent.excluded.size();
      for (auto expression :
           {retention->intent.condition, retention->intent.saveCondition,
            retention->intent.restoreCondition})
        if (expression)
          cost += expression.getTokens().size();
    }
    if (cost > 1048576 - compositeStrategyCost)
      return error("composite strategy provenance exceeds 1048576 work units");
    return strategyTransaction([&] {
      CompositeStrategyEdit record{target, std::move(edit), {}};
      for (const auto &leaf : physicalLeaves(target)) {
        if (applyStrategy(domains.at(leaf), record.edit, true) != TCL_OK)
          return TCL_ERROR;
        record.applied.insert(leaf);
      }
      if (validateStrategySupplier(record.edit) != TCL_OK)
        return TCL_ERROR;
      compositeStrategies.push_back(std::move(record));
      compositeStrategyCost += cost;
      Tcl_ResetResult(interp);
      return TCL_OK;
    });
  }
  int propagateStrategies() {
    // 5.10/8.3.3: membership updates change which leaves receive prior typed
    // contributions. Reapply only missing contributions, in source order;
    // existing leaf refinements and handle catalogs are never replaced.
    SmallVector<std::pair<size_t, std::string>> applied;
    for (auto [index, record] : llvm::enumerate(compositeStrategies))
      for (const auto &leaf : physicalLeaves(record.domain))
        if (!record.applied.count(leaf)) {
          if (applyStrategy(domains.at(leaf), record.edit) != TCL_OK) {
            for (auto &[previous, path] : applied)
              compositeStrategies[previous].applied.erase(path);
            return TCL_ERROR;
          }
          record.applied.insert(leaf);
          applied.emplace_back(index, leaf);
        }
    return TCL_OK;
  }
  int setRetention(Tcl_Size objc, Tcl_Obj *const objv[]) {
    // IEEE 1801-2018 6.50/8.3.2: merge explicit updates before applying any
    // defaults. Keep selectors and their provenance until register inference.
    Options opts;
    std::set<std::string> flags;
    for (Tcl_Size i = 2; i < objc; ++i) {
      StringRef option = Tcl_GetString(objv[i]);
      if (option == "-update" || option == "-no_retention" ||
          option == "-use_retention_as_primary") {
        if (!flags.insert(option.str()).second)
          return error("duplicate UPF option " + option);
        continue;
      }
      if (!llvm::is_contained(
              ArrayRef<StringRef>{"-domain", "-elements", "-exclude_elements",
                                  "-retention_supply", "-save_signal",
                                  "-restore_signal", "-save_condition",
                                  "-restore_condition", "-retention_condition",
                                  "-parameters"},
              option))
        return error("unsupported set_retention option: " + option);
      if (++i == objc)
        return error("missing value for " + option);
      if (!opts.emplace(option.str(), objv[i]).second)
        return error("duplicate UPF option " + option);
    }
    Domain *dom = domain(opts, true);
    if (!dom)
      return TCL_ERROR;
    std::string target = dom->name;
    StringRef name = Tcl_GetString(objv[1]);
    if (!identifier(name))
      return TCL_ERROR;
    Retention next;
    next.name = name.str();
    next.scope = scope;
    next.location = declarationLocation();
    next.sourceOrdinal = ++strategyOrdinal;
    auto selectors = [&](StringRef option, auto &target) {
      auto it = opts.find(option.str());
      if (it == opts.end())
        return true;
      std::vector<std::string> names;
      if (!list(it->second, names))
        return false;
      for (auto &name : names) {
        std::string path = object(name);
        if (path.empty()) {
          error("unknown or unsupported retention selector (whole signals and "
                "instances are supported): " +
                name);
          return false;
        }
        bool instance = objects.at(path)->getName().getStringRef() ==
                        "slang.symbol.instance";
        target.emplace(path, upf::RetentionElementAttr::get(
                                 module.getContext(),
                                 StringAttr::get(module.getContext(), path),
                                 instance ? upf::RetentionElementKind::Instance
                                          : upf::RetentionElementKind::Signal));
      }
      if (target.size() > 4096) {
        error("retention selection exceeds 4096 elements");
        return false;
      }
      return true;
    };
    if (!selectors("-elements", next.elements) ||
        !selectors("-exclude_elements", next.excluded))
      return TCL_ERROR;
    next.hasElements |= opts.count("-elements");
    next.noRetention |= flags.count("-no_retention");
    // IEEE 1801-2018 6.50/8.3.2: add the output-driver choice to the staged
    // strategy, preserving it across updates and rolling back caught errors.
    next.useRetentionAsPrimary |= flags.count("-use_retention_as_primary");
    auto trigger = [&](StringRef option, upf::RetentionTriggerAttr &target) {
      auto it = opts.find(option.str());
      if (it == opts.end())
        return true;
      std::vector<std::string> fields;
      if (!list(it->second, fields))
        return false;
      if (fields.size() != 2) {
        error("retention signal requires {logic_net high|low|posedge|negedge}");
        return false;
      }
      auto kind = upf::symbolizeRetentionTriggerKind(fields[1]);
      if (!kind) {
        error("retention signal sense must be high, low, posedge, or negedge");
        return false;
      }
      auto ref = reference(fields[0]);
      if (failed(ref))
        return false;
      if (ref->width != 1) {
        error("retention signal requires a scalar HDL reference");
        return false;
      }
      auto proposed = upf::RetentionTriggerAttr::get(
          module.getContext(), ref->token(module.getContext()), *kind);
      if (target && target != proposed) {
        error("conflicting or unsupported retention trigger refinement");
        return false;
      }
      target = proposed;
      return true;
    };
    auto condition = [&](StringRef option, upf::ExpressionAttr &target) {
      auto it = opts.find(option.str());
      if (it == opts.end())
        return true;
      // 6.50/5.4: names use the current command scope. Switch control aliases
      // and the special all-references-known rule of 6.22 do not apply.
      auto parsed = parseUPFBooleanExpression(
          Tcl_GetString(it->second), module.getContext(),
          [&](StringRef path) -> FailureOr<upf::ExpressionTokenAttr> {
            auto ref = reference(path);
            if (failed(ref))
              return failure();
            return ref->token(module.getContext());
          },
          [&](const llvm::Twine &message) { error(message); });
      if (failed(parsed))
        return false;
      if (target && target != *parsed) {
        error("conflicting or unsupported retention condition refinement");
        return false;
      }
      target = *parsed;
      return true;
    };
    if (!trigger("-save_signal", next.save) ||
        !trigger("-restore_signal", next.restore) ||
        !condition("-save_condition", next.saveCondition) ||
        !condition("-restore_condition", next.restoreCondition) ||
        !condition("-retention_condition", next.condition))
      return TCL_ERROR;
    if (auto it = opts.find("-parameters"); it != opts.end()) {
      std::vector<std::string> values;
      if (!list(it->second, values))
        return TCL_ERROR;
      std::set<std::string> parameters(values.begin(), values.end());
      for (StringRef flag : {"RET_SUP_COR", "SAV_RES_COR"})
        if (parameters.count(flag.str()) &&
            parameters.count(("NO_" + flag).str()))
          return error("conflicting retention corruption parameters");
      for (auto &value : values)
        if (value != "RET_SUP_COR" && value != "NO_RET_SUP_COR" &&
            value != "SAV_RES_COR" && value != "NO_SAV_RES_COR")
          return error("unsupported retention corruption parameter: " + value);
      if (parameters.count("RET_SUP_COR") || parameters.count("NO_RET_SUP_COR"))
        next.retentionSupplyCorrupt = parameters.count("RET_SUP_COR") != 0;
      if (parameters.count("SAV_RES_COR") || parameters.count("NO_SAV_RES_COR"))
        next.saveRestoreCorrupt = parameters.count("SAV_RES_COR") != 0;
    }
    RetentionEdit edit;
    edit.intent = std::move(next);
    edit.update = flags.count("-update");
    if (opts.count("-retention_supply")) {
      edit.supplier = supplySetKey(value(opts, "-retention_supply"));
    }
    return distributeStrategy(target, std::move(edit));
  }
  int run(StringRef command, Tcl_Size objc, Tcl_Obj *const objv[]) {
    Options opts;
    // IEEE 1801-2018 5.11: command failures are Tcl errors, so catch/proc
    // libraries observe the same error path as direct command invocations.
    if (objc < 2 && command != "upf_version")
      return error("missing argument for " + command);
    if (command == "set_retention")
      return setRetention(objc, objv);
    if (command == "upf_version") {
      if (objc > 2 || (objc == 2 && StringRef(Tcl_GetString(objv[1])) != "3.1"))
        return error(
            "this UPF frontend targets IEEE 1801-2018 (upf_version 3.1)");
      Tcl_SetObjResult(interp, Tcl_NewStringObj("3.1", -1));
      return TCL_OK;
    }
    if (command == "set_partial_on_translation") {
      // IEEE 1801-2018 6.47: one global setting across all files/scopes.
      // Repeating the setting is idempotent; a caught conflict preserves it.
      if (objc != 2)
        return error("usage: set_partial_on_translation OFF|FULL_ON");
      StringRef spelling = Tcl_GetString(objv[1]);
      upf::PartialOnTranslation next;
      if (spelling == "OFF")
        next = upf::PartialOnTranslation::Off;
      else if (spelling == "FULL_ON")
        next = upf::PartialOnTranslation::FullOn;
      else
        return error("PARTIAL_ON translation must be OFF or FULL_ON");
      if (partialOnTranslation && *partialOnTranslation != next)
        return error(
            "conflicting global PARTIAL_ON translation (IEEE 1801-2018 6.47)");
      partialOnTranslation = next;
      Tcl_SetObjResult(interp,
                       Tcl_NewStringObj(spelling.data(), spelling.size()));
      return TCL_OK;
    }
    if (command == "set_design_top") {
      // IEEE 1801-2018 6.42/4.3.7: this identifies the written-for MODULE;
      // it does not relocate the tool-established design-top instance/scope.
      if (objc != 2)
        return error("usage: set_design_top design_top_module");
      std::string name = Tcl_GetString(objv[1]);
      if (name.empty())
        return error("design top module must not be empty");
      designModule = name;
      Tcl_ResetResult(interp);
      return TCL_OK;
    }
    if (command == "set_scope") {
      // IEEE 1801-2018 6.52: return the PREVIOUS design-relative scope, and
      // never allow '..' to leave the current design-top instance.
      if (objc != 2)
        return error("usage: set_scope instance");
      if (top.empty())
        return error("UPF requires a unique elaborated design top; select one "
                     "with --top");
      std::string previous = rooted(scope);
      StringRef requested = Tcl_GetString(objv[1]);
      if (requested == "..") {
        if (scope == top)
          return error("set_scope .. cannot leave the design top");
        scope = queries.parent(scope);
      } else {
        std::string next = object(requested);
        if (next.empty() || !queries.isScope(next))
          return error("design scope not found: " +
                       StringRef(Tcl_GetString(objv[1])));
        scope = next;
      }
      Tcl_SetObjResult(interp, Tcl_NewStringObj(previous.c_str(), -1));
      return TCL_OK;
    }
    if (command == "load_upf") {
      // IEEE 1801-2018 6.33 and 8.3.1(a): scoped loads establish a fresh
      // top-instance/module/scope context for EACH requested instance.
      if (objc < 2 || !options(objc, objv, 2, {"-scope"}, opts))
        return TCL_ERROR;
      std::string oldFile = file;
      auto restoreFile = llvm::scope_exit([&] { file = oldFile; });
      file = Tcl_GetString(objv[1]);
      if (!opts.count("-scope")) {
        int result = Tcl_EvalFile(interp, file.c_str());
        if (result == TCL_OK)
          Tcl_ResetResult(interp);
        return result;
      }
      std::vector<std::string> instances;
      if (!list(opts["-scope"], instances))
        return TCL_ERROR;
      std::string oldScope = scope, oldTop = top, oldModel = designModule;
      auto restore = llvm::scope_exit([&] {
        scope = oldScope;
        top = oldTop;
        designModule = oldModel;
      });
      for (auto &instance : instances) {
        scope = oldScope;
        top = oldTop;
        if (StringRef(instance).starts_with('/'))
          return error(
              "load_upf -scope requires names rooted in current scope");
        std::string next = object(instance);
        if (next.empty() || objects.at(next)->getName().getStringRef() !=
                                "slang.symbol.instance")
          return error("load_upf scope not found: " + instance);
        scope = top = next;
        designModule = model(next);
        int result = Tcl_EvalFile(interp, file.c_str());
        if (result != TCL_OK)
          return result;
      }
      Tcl_ResetResult(interp);
      return TCL_OK;
    }
    if (top.empty())
      return error(
          "UPF requires a unique elaborated design top; select one with --top");
    if (command == "find_objects")
      return queries.find(interp, objc, objv, scope, top, supplyPortInfo);
    if (command == "create_power_domain" ||
        command == "create_composite_domain") {
      if (!creationScope(scope))
        return TCL_ERROR;
      RepeatedOptions repeated{{"-supply", {}}};
      if (objc < 2 || !options(objc, objv, 2,
                               {"-elements", "-exclude_elements", "-supply",
                                "-update", "-atomic", "-subdomains"},
                               opts, &repeated, {"-update", "-atomic"}))
        return TCL_ERROR;
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      std::string id = key(Tcl_GetString(objv[1]));
      auto found = domains.find(id);
      bool update = opts.count("-update");
      if (update && found == domains.end())
        return error("cannot update an unknown power domain");
      if (!update && found != domains.end())
        return error("duplicate power domain; use -update");
      if (update && opts.count("-atomic"))
        return error(
            "power-domain -atomic is not refinable (IEEE 1801-2018 6.20)");
      Domain dom = update ? found->second : Domain{};
      bool composite = command == "create_composite_domain" ||
                       opts.count("-subdomains") || dom.composite;
      if (composite &&
          (opts.count("-elements") || opts.count("-exclude_elements") ||
           opts.count("-atomic")))
        return error(
            "composite domains do not accept element selections or -atomic");
      if (update && composite && !dom.composite) {
        bool auxiliary = llvm::any_of(supplySets, [&](const auto &entry) {
          return entry.second.owner == dom.name && entry.first != dom.primary;
        });
        if (dom.hasElements || dom.hasExcluded || dom.atomic || auxiliary ||
            !dom.switchOutput.empty() || !dom.isolation.empty() ||
            !dom.retentions.empty())
          return error(
              "composite subdomains conflict with an existing physical "
              "domain definition");
      }
      dom.composite = composite;
      if (update) {
        if (dom.scope != scope)
          return error(
              "power-domain updates require the original execution scope");
      } else {
        if (hasNamedSet(Tcl_GetString(objv[1])))
          return error("power domain name conflicts with a supply set");
        if (hasNamedObject(Tcl_GetString(objv[1])))
          return error("power domain name conflicts with an existing object");
        dom.location = declarationLocation();
        dom.name = id;
        dom.scope = scope;
        dom.atomic = opts.count("-atomic");
        dom.primary =
            supplySetKey(std::string(Tcl_GetString(objv[1])) + ".primary");
      }
      // 5.9/6.20: preserve omitted versus explicit empty selections. Elements
      // aggregate as a set, and a later file may complete an empty base.
      dom.hasElements |= opts.count("-elements");
      dom.hasExcluded |= opts.count("-exclude_elements");
      auto selectors = [&](StringRef option, auto &aggregate) {
        auto found = opts.find(option.str());
        if (found == opts.end())
          return true;
        std::vector<std::string> names;
        if (!list(found->second, names))
          return false;
        for (auto &name : names) {
          std::string path = object(name);
          if (path.empty() || objects.at(path)->getName().getStringRef() !=
                                  "slang.symbol.instance") {
            error("power-domain element is not a design instance: " + name);
            return false;
          }
          if (!llvm::is_contained(aggregate, path))
            aggregate.push_back(path);
        }
        return true;
      };
      if (!selectors("-elements", dom.elements) ||
          !selectors("-exclude_elements", dom.excluded))
        return TCL_ERROR;
      if (opts.count("-subdomains")) {
        std::vector<std::string> names;
        if (!list(opts["-subdomains"], names))
          return TCL_ERROR;
        for (auto &name : names) {
          std::string child = key(name);
          if (child == id)
            return error("a composite domain cannot contain itself");
          if (!domains.count(child))
            return error("unknown composite subdomain: " + name);
          if (!llvm::is_contained(dom.subdomains, child))
            dom.subdomains.push_back(child);
        }
      }
      // A later update can introduce a back edge. Check the staged graph
      // before reserving handles or committing electrical associations.
      std::set<std::string> seen;
      std::vector<std::string> pending = dom.subdomains;
      while (!pending.empty()) {
        std::string child = std::move(pending.back());
        pending.pop_back();
        if (child == id)
          return error("cycle in composite domain composition");
        if (seen.insert(child).second) {
          auto &children = domains.at(child).subdomains;
          pending.insert(pending.end(), children.begin(), children.end());
        }
      }
      std::map<std::string, SupplySet> handles;
      auto makeHandle = [&](const std::string &id) {
        if (supplySets.count(id) || handles.count(id))
          return;
        SupplySet handle;
        handle.scope = scope;
        handle.handle = true;
        handle.owner = dom.name;
        // 8.3.2: subordinate objects retain their creation execution scope.
        handle.updateScope = scope;
        handle.location = dom.location;
        if (id == dom.primary)
          handle.required = {"power", "ground"};
        handles.emplace(id, std::move(handle));
      };
      makeHandle(dom.primary);
      std::vector<std::pair<std::string, std::string>> associations;
      for (auto option : repeated["-supply"]) {
        std::vector<std::string> fields;
        if (!list(option, fields))
          return TCL_ERROR;
        if (fields.empty() || fields.size() > 2)
          return error("domain supply requires {handle [supply_set]}");
        if (!identifier(fields[0]))
          return TCL_ERROR;
        if (composite && fields[0] != "primary")
          return error("composite domains only have the primary supply handle");
        if (dom.retentions.count(fields[0]) || dom.isolationName == fields[0])
          return error("domain supply handle conflicts with a strategy: " +
                       fields[0]);
        std::string id =
            supplySetKey(std::string(Tcl_GetString(objv[1])) + "." + fields[0]);
        makeHandle(id);
        if (fields.size() == 2)
          associations.emplace_back(id, supplySetKey(fields[1]));
      }
      for (auto &[a, b] : associations)
        if (!supplySets.count(b) && !handles.count(b))
          return error("unknown supply set: " + b);
      std::string primary = dom.primary;
      // 5.10: a caught failure must preserve the extent, handle identities,
      // catalogs and all associations; commit only after every row validates.
      auto commit = [&] {
        domains.insert_or_assign(id, std::move(dom));
        supplySets.insert(handles.begin(), handles.end());
        setAssociations.insert(setAssociations.end(), associations.begin(),
                               associations.end());
        for (auto &[a, b] : associations)
          if (a == primary || b == primary)
            markPrimaryAssociations({a, b});
        int result = composite ? propagateStrategies() : TCL_OK;
        if (result == TCL_OK)
          Tcl_ResetResult(interp);
        return result;
      };
      if (composite && !compositeStrategies.empty())
        return strategyTransaction(commit);
      return commit();
    }
    if (command == "add_power_state") {
      // IEEE 1801-2018 5.10/6.5: stage catalog, command scope, requirements
      // and completion together. A caught error commits none of those fields.
      StringRef objectName;
      bool sawObject = false;
      bool update = false, complete = false, supplyKind = false;
      std::vector<Tcl_Obj *> rows;
      for (Tcl_Size i = 1; i < objc; ++i) {
        StringRef word = Tcl_GetString(objv[i]);
        if (word == "-state") {
          if (++i == objc)
            return error("missing value for -state");
          rows.push_back(objv[i]);
        } else if (word == "-update") {
          if (update)
            return error("duplicate UPF option -update");
          update = true;
        } else if (word == "-complete") {
          if (complete)
            return error("duplicate UPF option -complete");
          complete = true;
        } else if (word == "-supply") {
          if (supplyKind)
            return error("duplicate UPF option -supply");
          supplyKind = true;
        } else if (word.starts_with('-'))
          return error("unsupported add_power_state option: " + word);
        else if (sawObject)
          return error("add_power_state requires one object name");
        else {
          objectName = word;
          sawObject = true;
        }
      }
      if (objectName.empty())
        return error("add_power_state requires a supply set or handle");
      std::string id = supplySetKey(objectName);
      auto found = supplySets.find(id);
      if (found == supplySets.end())
        return error("unknown supply set or handle: " + objectName);
      SupplySet set = found->second;
      if (set.stateScope && !update)
        return error("subsequent add_power_state commands require -update");
      if (set.stateScope && *set.stateScope != scope)
        return error(
            "power-state updates must use the original execution scope");
      bool first = !set.stateScope;
      set.stateScope = scope;
      bool touchesPredefined = false;
      for (auto row : rows) {
        std::vector<std::string> fields;
        if (!list(row, fields))
          return TCL_ERROR;
        if (!fields.empty() && (fields[0] == "ON" || fields[0] == "OFF"))
          touchesPredefined = true;
      }
      // 6.5.4's first ON examples omit -update; informative Annex E.4.4.3
      // requires it. Accept either first spelling for predefined states;
      // preserve normal command-history rules for new states/later calls.
      if (first && update && !touchesPredefined)
        return error(
            "a first command defining new power states must omit -update");
      Location stateLocation = declarationLocation();
      size_t catalogTokens = 0;
      for (auto &[name, state] : set.states)
        if (state.condition)
          catalogTokens += state.condition->tokens.size();
      for (auto row : rows) {
        std::vector<std::string> fields;
        if (!list(row, fields))
          return TCL_ERROR;
        if (fields.empty())
          return error("power state requires a name");
        std::string name = fields.front();
        if (StringRef(name).contains('.'))
          return error(
              "hierarchical power-state refinements are not implemented");
        if (!identifier(name))
          return TCL_ERROR;
        if (name == "ERROR" || name == "UNDEFINED")
          return error("explicit edits of ERROR/UNDEFINED power states are not "
                       "implemented");
        bool predefined = name == "ON" || name == "OFF";
        if (!set.states.count(name) && set.states.size() == 256)
          return error(
              "power-state catalog exceeds 256 states or 65536 tokens");
        if (set.complete && !predefined && !set.states.count(name))
          return error("cannot add a fundamental power state after -complete");
        SupplySet::State state;
        if (auto previous = set.states.find(name); previous != set.states.end())
          state = previous->second;
        else if (predefined)
          state.simstate =
              name == "ON" ? upf::Simstate::Normal : upf::Simstate::Corrupt;
        size_t oldTokens = state.condition ? state.condition->tokens.size() : 0;
        std::set<std::string> options;
        for (size_t i = 1; i < fields.size(); ++i) {
          StringRef option = fields[i];
          if (!options.insert(option.str()).second)
            return error("duplicate power-state option: " + option);
          if (option == "-illegal" || option == "-legal") {
            if (options.count(option == "-legal" ? "-illegal" : "-legal"))
              return error(
                  "power state cannot specify both -legal and -illegal");
            if (state.illegal && option == "-legal")
              return error("illegal power states cannot be made legal");
            state.illegal = option == "-illegal";
          } else if (option == "-simstate") {
            if (++i == fields.size())
              return error("missing value for -simstate");
            upf::Simstate next;
            if (fields[i] == "NORMAL")
              next = upf::Simstate::Normal;
            else if (fields[i] == "CORRUPT")
              next = upf::Simstate::Corrupt;
            else if (fields[i] == "NOT_NORMAL")
              next = upf::Simstate::NotNormal;
            else
              return error("unsupported power-state simstate: " + fields[i]);
            if (state.simstate != upf::Simstate::Unspecified &&
                state.simstate != next &&
                !(state.simstate == upf::Simstate::NotNormal &&
                  next != upf::Simstate::Normal))
              return error("power-state simstate conflicts with its previous "
                           "definition");
            state.simstate = next;
          } else if (option == "-supply_expr") {
            if (++i == fields.size())
              return error("missing value for -supply_expr");
            auto resolve = [&](StringRef name) -> FailureOr<SupplyReference> {
              std::optional<SupplyObject> object;
              if (llvm::is_contained(upf::getSupplyFunctionNames(), name))
                object = function(id, name);
              else {
                name.consume_front("./");
                object = supply(name, true);
              }
              if (!object) {
                error("unknown supply expression reference: " + name);
                return failure();
              }
              SupplyReference reference{*object, {}, {}};
              if (object->kind == SupplyObject::Function) {
                StringRef field = StringRef(object->path).rsplit('.').second;
                if (*object != function(id, field)) {
                  error("supply expression cannot reference another supply "
                        "set's function (IEEE 1801-2018 6.5.6a)");
                  return failure();
                }
                reference.function = field.str();
                reference.required.insert(field.str());
              }
              return reference;
            };
            auto expression = parseSupplyExpression(
                fields[i], resolve,
                [&](const llvm::Twine &message) { error(message); });
            if (failed(expression))
              return TCL_ERROR;
            auto contradiction = contradictsSupplyExpression(
                *expression, [&](const SupplyObject &a, const SupplyObject &b) {
                  return sameSupply(a, b);
                });
            if (!contradiction)
              return error("supply-expression consistency check exceeds 256 "
                           "branches or 65536 work units");
            if (*contradiction)
              return error("contradictory supply expression (IEEE 1801-2018 "
                           "5.10/6.5.2)");
            if (state.condition &&
                !refinesSupplyExpression(
                    *state.condition, *expression,
                    [&](const SupplyObject &a, const SupplyObject &b) {
                      return sameSupply(a, b);
                    }))
              return error(
                  "conflicting or unsupported supply-expression refinement");
            set.required.insert(expression->required.begin(),
                                expression->required.end());
            state.condition = std::move(*expression);
            state.location = stateLocation;
          } else
            return error("unsupported power-state option: " + option);
        }
        size_t newTokens = state.condition ? state.condition->tokens.size() : 0;
        catalogTokens = catalogTokens - oldTokens + newTokens;
        if (catalogTokens > 65536)
          return error(
              "power-state catalog exceeds 256 states or 65536 tokens");
        set.states.insert_or_assign(name, std::move(state));
      }
      size_t tokens = 0;
      for (auto &[name, state] : set.states)
        if (state.condition)
          tokens += state.condition->tokens.size();
      if (set.states.size() > 256 || tokens > 65536)
        return error("power-state catalog exceeds 256 states or 65536 tokens");
      set.complete |= complete;
      supplySets.insert_or_assign(id, std::move(set));
      Tcl_ResetResult(interp);
      return TCL_OK;
    }
    if (command == "create_supply_set") {
      // IEEE 1801-2018 6.26/5.10: handles already exist, updates refine
      // rather than replace bindings, and repeated identical bindings are OK.
      bool update = false;
      std::vector<Tcl_Obj *> bindings;
      for (Tcl_Size i = 2; i < objc; ++i) {
        StringRef option = Tcl_GetString(objv[i]);
        if (option == "-update") {
          if (update)
            return error("duplicate UPF option -update");
          update = true;
        } else if (option == "-function") {
          if (++i == objc)
            return error("missing value for -function");
          bindings.push_back(objv[i]);
        } else
          return error("unsupported create_supply_set option: " + option);
      }
      StringRef local = Tcl_GetString(objv[1]);
      std::string id = supplySetKey(local);
      auto found = supplySets.find(id);
      if (found != supplySets.end() && !update)
        return error("existing supply set or handle requires -update");
      if (found == supplySets.end()) {
        if (!creationScope(scope))
          return TCL_ERROR;
        if (update)
          return error("cannot update unknown supply set or handle");
        if (local.contains('.'))
          return error("unknown supply set handle");
        if (!identifier(local))
          return TCL_ERROR;
        if (hasNamedObject(local))
          return error("supply set name conflicts with an existing object");
      }
      SupplySet set = found == supplySets.end() ? SupplySet{} : found->second;
      if (set.updateScope && *set.updateScope != scope)
        return error(
            "supply set updates must use the original execution scope");
      set.updateScope = scope;
      if (found == supplySets.end()) {
        set.scope = scope;
        set.location = declarationLocation();
      }
      std::set<std::string> associated;
      for (auto binding : bindings) {
        std::vector<std::string> fields;
        if (!list(binding, fields))
          return TCL_ERROR;
        if (fields.size() != 2)
          return error(
              "supply function requires {function supply_net_or_port}");
        if (!llvm::is_contained(upf::getSupplyFunctionNames(), fields[0]))
          return error("unknown supply set function: " + fields[0]);
        auto object = supply(fields[1], true);
        if (!object)
          return error("unknown supply net, port, or function: " + fields[1]);
        if (!functionSupply(*object))
          return TCL_ERROR;
        auto [previous, inserted] = set.functions.emplace(fields[0], *object);
        if (!inserted && !sameSupply(previous->second, *object, id, &set))
          return error("supply function is already associated with a different "
                       "supply: " +
                       fields[0]);
        if (fields[0] == "power" || fields[0] == "ground")
          associated.insert(id);
        if (object->kind == SupplyObject::Function &&
            (StringRef(object->path).ends_with(".power") ||
             StringRef(object->path).ends_with(".ground")))
          associated.insert(StringRef(object->path).rsplit('.').first.str());
      }
      supplySets.insert_or_assign(id, std::move(set));
      markPrimaryAssociations(std::move(associated));
      Tcl_ResetResult(interp);
      return TCL_OK;
    }
    if (command == "associate_supply_set") {
      // 6.10: electrical links persist independently of per-set state tables.
      if (!options(objc, objv, 2, {"-handle"}, opts))
        return TCL_ERROR;
      std::vector<std::string> names;
      if (!list(objv[1], names))
        return TCL_ERROR;
      if (opts.count("-handle"))
        names.push_back(value(opts, "-handle").str());
      if (names.size() < 2)
        return error("supply association requires at least two supply sets");
      for (auto &name : names) {
        name = supplySetKey(name);
        if (!supplySets.count(name))
          return error("unknown supply set or handle: " + name);
      }
      if (opts.count("-handle") && !supplySets.at(names.back()).handle)
        return error("-handle requires a supply set handle");
      std::optional<std::pair<std::string, std::string>> binding;
      if (opts.count("-handle") &&
          !supplySets.at(names.back()).strategy.empty()) {
        std::set<std::string> suppliers(names.begin(), names.end() - 1);
        suppliers.erase(names.back());
        if (suppliers.size() > 1)
          return error("strategy supply handle cannot associate more than one "
                       "supply set: " +
                       names.back());
        if (!suppliers.empty()) {
          binding = std::make_pair(names.back(), *suppliers.begin());
          if (!strategyBinding(binding->first, binding->second))
            return TCL_ERROR;
        }
      }
      SmallVector<std::pair<std::string, std::string>> links;
      for (auto &name : ArrayRef(names).drop_front())
        if (name != names.front())
          links.emplace_back(names.front(), name);
      setAssociations.insert(setAssociations.end(), links.begin(), links.end());
      if (binding) {
        auto &target = supplySets.at(binding->first);
        target.binding = binding->second;
        target.explicitStrategySupply = true;
      }
      markPrimaryAssociations(
          std::set<std::string>(names.begin(), names.end()));
      Tcl_ResetResult(interp);
      return TCL_OK;
    }
    if (command == "create_supply_net" || command == "create_supply_port") {
      // IEEE 1801-2018 6.24.1/6.25: -domain selects the declaration scope.
      // For nets it also records domain availability, which -reuse extends
      // without creating a second net or changing its electrical identity.
      if (objc < 2)
        return error("supply declaration requires a name");
      if (command == "create_supply_net") {
        if (!options(objc, objv, 2, {"-domain", "-resolve", "-reuse"}, opts,
                     nullptr, {"-reuse"}))
          return TCL_ERROR;
      } else if (!options(objc, objv, 2, {"-domain", "-direction"}, opts))
        return TCL_ERROR;
      StringRef direction = value(opts, "-direction");
      if (!direction.empty() && direction != "in" && direction != "out" &&
          direction != "inout")
        return error("supply-port direction must be in, out, or inout");
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      bool reuse = opts.count("-reuse");
      if (reuse && !opts.count("-domain"))
        return error("supply-net -reuse requires -domain");
      std::string previousScope = scope;
      auto restoreScope = llvm::scope_exit([&] { scope = previousScope; });
      Domain *owner = nullptr;
      if (opts.count("-domain")) {
        owner = domain(opts);
        if (!owner)
          return TCL_ERROR;
        scope = owner->scope;
      }
      if (!creationScope(scope))
        return TCL_ERROR;
      std::string name = key(Tcl_GetString(objv[1]));
      if (reuse) {
        auto found = domainNets.find(name);
        if (found == domainNets.end())
          return error("supply-net -reuse requires an existing net created "
                       "with -domain in the same creation scope");
        const auto &original = found->second;
        if (original.scope != scope || original.owner == owner->name)
          return error("supply-net -reuse requires another power domain in "
                       "the same creation scope");
        if (opts.count("-resolve") &&
            value(opts, "-resolve") != original.resolution)
          return error("supply-net -reuse resolution conflicts with the "
                       "original net");
        // Repeated reuse by an already admitted domain is idempotent. The
        // original domain, scope and resolution are never replaced (6.24.1).
        found->second.domains.insert(owner->name);
        Tcl_ResetResult(interp);
        return TCL_OK;
      }
      if (opts.count("-resolve") && value(opts, "-resolve") != "unresolved")
        return error("the first UPF slice supports unresolved supply nets");
      auto &inventory = command == "create_supply_net" ? nets : supplyPorts;
      if (hasNamedSet(Tcl_GetString(objv[1])))
        return error("supply object name conflicts with a supply set");
      if (inventory.count(key(Tcl_GetString(objv[1]))))
        return error("duplicate supply object");
      if (declaredHDLNames.count(key(Tcl_GetString(objv[1]))))
        // 8.3.4 permits reuse only of an appropriate HDL supply_net_type
        // object. This frontend has no implemented-object linkage yet;
        // silently creating a separate UPF root would lose HDL connectivity.
        return error("supply object name conflicts with an HDL object; "
                     "HDL supply-object reuse is not implemented");
      if (hasNamedObject(Tcl_GetString(objv[1]), true))
        return error("supply object name conflicts with an existing object");
      inventory.insert(key(Tcl_GetString(objv[1])));
      if (command == "create_supply_net" && owner)
        domainNets.emplace(
            name, DomainNet{scope, owner->name, "unresolved", {owner->name}});
      if (command == "create_supply_port")
        supplyPortInfo[key(Tcl_GetString(objv[1]))] = {
            direction == "out"     ? SupplyPort::Out
            : direction == "inout" ? SupplyPort::InOut
                                   : SupplyPort::In,
            false};
      return TCL_OK;
    }
    if (command == "connect_supply_net") {
      if (objc < 2 || !options(objc, objv, 2, {"-ports"}, opts))
        return TCL_ERROR;
      auto net = supply(Tcl_GetString(objv[1]));
      if (!net)
        return error("unknown supply net");
      std::vector<std::string> ports;
      if (!opts.count("-ports"))
        return error("connect_supply_net requires -ports");
      if (!list(opts["-ports"], ports))
        return TCL_ERROR;
      for (auto &port : ports) {
        if (!supplyPorts.count(key(port)))
          return error("unknown supply port: " + port);
        if (supplyPortInfo.at(key(port)).direction == SupplyPort::InOut)
          return error("inout supply connections are not implemented: " + port);
      }
      auto bindings = supplyBindings;
      for (auto &port : ports)
        if (failed(bindSupply(
                *net, key(port), bindings,
                [&](const llvm::Twine &message) { error(message); },
                [&](const SupplyObject &a, const SupplyObject &b) {
                  return sameSupply(a, b, {}, nullptr, &bindings);
                })))
          return TCL_ERROR;
      supplyBindings = std::move(bindings);
      return TCL_OK;
    }
    if (command == "set_domain_supply_net") {
      // IEEE 1801-2018 6.43: both primary associations are required, they may
      // be made only once, and success returns the Tcl integer 1.
      if (objc < 2 ||
          !options(objc, objv, 2, {"-primary_power_net", "-primary_ground_net"},
                   opts))
        return TCL_ERROR;
      auto found = domains.find(key(Tcl_GetString(objv[1])));
      if (found == domains.end())
        return error("unknown power domain");
      if (found->second.composite)
        return error("legacy supply association on composite domains is not implemented");
      if (!opts.count("-primary_power_net") ||
          !opts.count("-primary_ground_net"))
        return error("both primary power and ground nets are required");
      if (found->second.primaryAssociated)
        return error("domain primary supply is already associated");
      // IEEE 1801-2018 5.5/6.43: this is equivalent to declaring a supply
      // set in the CALLER's scope and associating it with the domain handle.
      // Unlike create_supply_net/port/switch -domain, it never relocates the
      // source-name lookup to the domain's creation scope.
      auto power = supply(value(opts, "-primary_power_net"), true);
      auto ground = supply(value(opts, "-primary_ground_net"), true);
      if (!power || !ground)
        return error("unknown primary supply net");
      if (!functionSupply(*power) || !functionSupply(*ground))
        return TCL_ERROR;
      // 6.43 creates a fresh supplying set, not just two direct bindings on
      // PD.primary. Its unmodified 4.7.4 ON policy still requires FULL_ON
      // when PD.primary overrides ON to admit PARTIAL_ON or ignore ground.
      // Preserve the primary's catalog/scope and propagate all six functions
      // and their requiredness through the ordinary association path (6.10).
      std::string stem = "$legacy_primary:" + found->first;
      std::string local = stem;
      uint64_t suffix = 0;
      // The private spelling is not a UPF identifier, but can still coincide
      // with an escaped HDL declaration. Keep the caller namespace unique.
      while (hasNamedObject(local) ||
             declaredHDLNames.count(scope + ".\\" + local + " "))
        local = stem + "_" + std::to_string(++suffix);
      std::string supplierName = supplySetKey(local);
      SupplySet supplier;
      supplier.scope = scope;
      supplier.updateScope = scope;
      supplier.location = declarationLocation();
      supplier.functions = {{"power", *power}, {"ground", *ground}};
      supplier.privateSupplier = true;
      if (!supplySets.emplace(supplierName, std::move(supplier)).second)
        return error("implicit legacy primary supplier already exists");
      setAssociations.emplace_back(supplierName, found->second.primary);
      found->second.primaryAssociated = true;
      std::set<std::string> associated{found->second.primary, supplierName};
      for (auto object : {*power, *ground})
        if (object.kind == SupplyObject::Function &&
            (StringRef(object.path).ends_with(".power") ||
             StringRef(object.path).ends_with(".ground")))
          associated.insert(StringRef(object.path).rsplit('.').first.str());
      markPrimaryAssociations(std::move(associated));
      Tcl_SetObjResult(interp, Tcl_NewIntObj(1));
      return TCL_OK;
    }
    if (command == "create_power_switch") {
      // IEEE 1801-2018 6.22: -domain uses the owning domain's scope, and
      // control expressions reference the switch's declared control-port names.
      RepeatedOptions repeated{{"-control_port", {}},
                               {"-on_state", {}},
                               {"-on_partial_state", {}},
                               {"-error_state", {}}};
      if (objc < 2 ||
          !options(objc, objv, 2,
                   {"-domain", "-input_supply_port", "-output_supply_port",
                    "-control_port", "-on_state", "-on_partial_state",
                    "-off_state", "-error_state"},
                   opts, &repeated))
        return TCL_ERROR;
      Domain *dom = domain(opts);
      if (!dom)
        return TCL_ERROR;
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      std::string previousScope = scope;
      auto restoreScope = llvm::scope_exit([&] { scope = previousScope; });
      scope = dom->scope;
      if (!creationScope(scope))
        return TCL_ERROR;
      if (hasNamedSet(Tcl_GetString(objv[1])))
        return error("power switch name conflicts with a supply set");
      if (!dom->switchOutput.empty())
        return error("one power switch per domain is supported");
      if (switches.count(key(Tcl_GetString(objv[1]))))
        return error("duplicate power switch");
      if (hasNamedObject(Tcl_GetString(objv[1])))
        return error("power switch name conflicts with an existing object");
      std::vector<std::string> input, output;
      for (StringRef required : {"-input_supply_port", "-output_supply_port"})
        if (!opts.count(required.str()))
          return error("missing power-switch option " + required);
      if (!list(opts["-input_supply_port"], input) ||
          !list(opts["-output_supply_port"], output))
        return TCL_ERROR;
      if (input.size() != 2 || output.size() != 2)
        return error("expected single input/output supply");
      if (!identifier(input[0]) || !identifier(output[0]))
        return TCL_ERROR;
      if (input[0] == output[0])
        return error("duplicate power-switch port name");
      auto inputSupply = supply(input[1]), outputSupply = supply(output[1]);
      if (!inputSupply || !outputSupply)
        return error("power switch references an unknown supply net");
      if (*inputSupply == *outputSupply)
        return error("a switch must have distinct input and output supplies");
      std::map<std::string, ControlReference> aliases;
      for (auto port : repeated["-control_port"]) {
        std::vector<std::string> pair;
        if (!list(port, pair))
          return TCL_ERROR;
        if (pair.size() != 2)
          return error("control port requires {alias design_object}");
        if (!identifier(pair[0]))
          return TCL_ERROR;
        if (pair[0] == input[0] || pair[0] == output[0] ||
            aliases.count(pair[0]))
          return error("duplicate power-switch port name: " + pair[0]);
        auto resolved = reference(pair[1]);
        if (failed(resolved))
          return TCL_ERROR;
        // IEEE 1801-2018 6.22/10.6.1.11 model a switch control as a logic
        // port. Keep scalar bindings; direct vector references require the
        // explicit HDL-expression extension rather than inheriting net ranges.
        if (resolved->width != 1)
          return error("power-switch control port requires a one-bit integral "
                       "design object; reference vectors directly: " +
                       pair[1]);
        // A created UPF logic port is scalar unsigned logic (6.19/6.22).
        auto scalar =
            slangir::IntegralType::get(module.getContext(), 1, false, true, 0,
                                       0, slangir::IntegralFlavor::Logic);
        resolved->types =
            ArrayAttr::get(module.getContext(), {TypeAttr::get(scalar)});
        resolved->signs = DenseBoolArrayAttr::get(module.getContext(), {false});
        resolved->stage = 0;
        resolved->isSigned = false;
        aliases.emplace(pair[0], *resolved);
      }
      auto resolveControl =
          [&](StringRef name) -> FailureOr<upf::ExpressionTokenAttr> {
        auto found = aliases.find(name.str());
        if (found != aliases.end())
          return found->second.token(module.getContext());
        // IEEE 1801-2018 6.22 restricts switch expressions to control ports.
        // Direct HDL names use the broader 5.4 grammar only as an opt-in
        // extension; do not silently treat it as the command's standard form.
        if (!allowHDLExpressions) {
          error("unknown power-switch control port '" + name +
                "'; bind it with -control_port (direct HDL references require "
                "--upf-allow-hdl-expressions)");
          return failure();
        }
        auto resolved = reference(name, &aliases);
        if (failed(resolved))
          return failure();
        return resolved->token(module.getContext());
      };
      auto report = [&](const llvm::Twine &message) { error(message); };
      size_t count = repeated["-on_state"].size() +
                     repeated["-on_partial_state"].size() +
                     repeated["-error_state"].size() + opts.count("-off_state");
      if (count > 256)
        return error("power switch exceeds 256 states");
      std::set<std::string> stateNames;
      size_t tokens = 0;
      auto state = [&](Tcl_Obj *obj,
                       bool on) -> FailureOr<upf::SwitchStateAttr> {
        std::vector<std::string> fields;
        if (!list(obj, fields))
          return failure();
        if (fields.size() != (on ? 3u : 2u)) {
          error(on ? "on state requires {name input_supply_port expression}"
                   : "off/error state requires {name expression}");
          return failure();
        }
        if (!identifier(fields[0]))
          return failure();
        if (!stateNames.insert(fields[0]).second) {
          error("duplicate power-switch state name: " + fields[0]);
          return failure();
        }
        if (on && fields[1] != input[0]) {
          error("on-state references an unknown input supply port");
          return failure();
        }
        auto expression = parseUPFBooleanExpression(
            fields.back(), module.getContext(), resolveControl, report);
        if (failed(expression))
          return failure();
        tokens += expression->getTokens().size();
        if (tokens > 65536) {
          error("power switch exceeds 65536 expression tokens");
          return failure();
        }
        return upf::SwitchStateAttr::get(
            module.getContext(),
            StringAttr::get(module.getContext(), fields[0]), *expression);
      };
      SmallVector<Attribute> onStates, partialStates, errorStates;
      for (auto obj : repeated["-on_state"]) {
        auto parsed = state(obj, true);
        if (failed(parsed))
          return TCL_ERROR;
        onStates.push_back(*parsed);
      }
      for (auto obj : repeated["-on_partial_state"]) {
        auto parsed = state(obj, true);
        if (failed(parsed))
          return TCL_ERROR;
        partialStates.push_back(*parsed);
      }
      upf::SwitchStateAttr offState;
      if (auto found = opts.find("-off_state"); found != opts.end()) {
        auto parsed = state(found->second, false);
        if (failed(parsed))
          return TCL_ERROR;
        offState = *parsed;
      }
      for (auto obj : repeated["-error_state"]) {
        auto parsed = state(obj, false);
        if (failed(parsed))
          return TCL_ERROR;
        errorStates.push_back(*parsed);
      }
      // IEEE 1801-2018 6.24.3: unresolved supplies cannot have multiple
      // drivers. This slice also requires independently powered input rails;
      // reject switch cascades in either declaration order (9.2.2-9.2.3).
      for (auto &[name, other] : domains) {
        if (&other == dom || other.switchOutput.empty())
          continue;
        if (other.outputSupply == outputSupply)
          return error(
              "multiple switches drive the same unresolved supply net");
        if (other.outputSupply == inputSupply ||
            other.inputSupply == outputSupply)
          return error("cascaded power switches are not implemented");
      }
      std::string switchName = key(Tcl_GetString(objv[1]));
      std::string inputPort = switchName + "." + input[0];
      std::string outputPort = switchName + "." + output[0];
      if (supplyPorts.count(inputPort) || supplyPorts.count(outputPort))
        return error("power-switch supply port already exists");
      auto bindings = supplyBindings;
      for (auto [net, port] : {std::make_pair(*inputSupply, inputPort),
                               std::make_pair(*outputSupply, outputPort)})
        if (failed(bindSupply(
                net, port, bindings,
                [&](const llvm::Twine &message) { error(message); })))
          return TCL_ERROR;
      if (!switches.insert(switchName).second)
        return error("duplicate power switch");
      dom->on = std::move(onStates);
      dom->partial = std::move(partialStates);
      dom->off = offState;
      dom->errors = std::move(errorStates);
      dom->switchInput = inputSupply->path;
      dom->switchOutput = outputSupply->path;
      dom->inputSupply = *inputSupply;
      dom->outputSupply = *outputSupply;
      dom->inputPort = inputPort;
      dom->outputPort = outputPort;
      supplyPorts.insert(inputPort);
      supplyPorts.insert(outputPort);
      supplyPortInfo[inputPort] = {SupplyPort::In, false};
      supplyPortInfo[outputPort] = {SupplyPort::Out, true};
      supplyBindings = std::move(bindings);
      return TCL_OK;
    }
    if (command == "set_isolation") {
      // IEEE 1801-2018 6.45: this first slice handles parent-located output
      // isolation; other strategy forms must fail rather than be ignored.
      bool diffSupplyOnly = true, sawDiffSupplyOnly = false;
      for (Tcl_Size i = 2; i < objc; ++i) {
        StringRef option = Tcl_GetString(objv[i]);
        if (option == "-diff_supply_only") {
          // 6.45 makes both omission and a bare option TRUE. Preserve the
          // next option, and stage the result until all validation succeeds.
          if (sawDiffSupplyOnly)
            return error("duplicate UPF option -diff_supply_only");
          sawDiffSupplyOnly = true;
          if (i + 1 < objc &&
              !StringRef(Tcl_GetString(objv[i + 1])).starts_with('-')) {
            int flag;
            if (Tcl_GetBooleanFromObj(interp, objv[++i], &flag) != TCL_OK)
              return TCL_ERROR;
            diffSupplyOnly = flag;
          }
          continue;
        }
        if (!llvm::is_contained(
                ArrayRef<StringRef>{"-domain", "-isolation_signal",
                                    "-isolation_sense", "-clamp_value",
                                    "-applies_to", "-location"},
                option))
          return error("unsupported UPF option '" + option +
                       "' in set_isolation");
        if (++i == objc)
          return error("missing value for " + option);
        if (!opts.emplace(option.str(), objv[i]).second)
          return error("duplicate UPF option " + option);
      }
      Domain *dom = domain(opts, true);
      if (!dom)
        return TCL_ERROR;
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      StringRef isolationName = Tcl_GetString(objv[1]);
      if (value(opts, "-applies_to") != "outputs" ||
          value(opts, "-location") != "parent")
        return error("initial isolation support requires -applies_to outputs "
                     "-location parent");
      std::string isolation;
      if (!control(value(opts, "-isolation_signal"), isolation))
        return TCL_ERROR;
      StringRef sense = value(opts, "-isolation_sense");
      if (!sense.empty() && sense != "high" && sense != "low")
        return error("isolation sense must be high or low");
      StringRef clamp = value(opts, "-clamp_value");
      if (clamp != "0" && clamp != "1")
        return error("initial isolation clamp must be 0 or 1");
      IsolationEdit edit;
      edit.name = isolationName.str();
      edit.scope = scope;
      edit.location = declarationLocation();
      edit.control = std::move(isolation);
      edit.high = sense != "low";
      edit.clamp = clamp == "1";
      edit.diffSupplyOnly = diffSupplyOnly;
      return distributeStrategy(dom->name, std::move(edit));
    }
    return error("unsupported UPF command: " + command);
  }
};
struct Command {
  Session *session;
  const char *name;
};
int dispatch(void *data, Tcl_Interp *, Tcl_Size objc, Tcl_Obj *const objv[]) {
  auto &command = *static_cast<Command *>(data);
  return command.session->run(command.name, objc, objv);
}
} // namespace
#endif
LogicalResult executeUPF(ModuleOp module, llvm::ArrayRef<std::string> paths,
                         StringRef resourceDir, StringRef executablePath,
                         bool allowHDLExpressions, bool assumePoweredInputs) {
  if (paths.empty())
    return success();
  module.getContext()->getOrLoadDialect<upf::UPFDialect>();
#ifndef TALOS_ENABLE_UPF
  return module.emitError(
      "UPF is disabled; configure with TALOS_ENABLE_UPF=ON");
#else
  static std::once_flag initialized;
  // IEEE 1801-2018 5.1: preserve full core introspection and relative
  // libraries.
  std::call_once(initialized,
                 [&] { Tcl_FindExecutable(executablePath.str().c_str()); });
  std::unique_ptr<Tcl_Interp, decltype(&Tcl_DeleteInterp)> interp(
      Tcl_CreateInterp(), Tcl_DeleteInterp);
  llvm::SmallString<256> library(resourceDir);
  llvm::sys::path::append(library, "tcl9.0");
  if (!llvm::sys::fs::is_directory(library))
    library = TALOS_TCL_LIBRARY_DIR;
  Tcl_SetVar(interp.get(), "tcl_library", library.c_str(), TCL_GLOBAL_ONLY);
  if (Tcl_Init(interp.get()) != TCL_OK)
    return module.emitError() << "could not initialize Tcl core: "
                              << Tcl_GetStringResult(interp.get());
  Session session(module, interp.get(), allowHDLExpressions);
  std::vector<Command> commands;
  for (const char *name :
       {"upf_version", "set_design_top", "set_scope", "find_objects",
        "load_upf", "create_power_domain", "create_composite_domain",
        "create_supply_net", "create_supply_port", "connect_supply_net",
        "set_domain_supply_net", "create_power_switch", "set_isolation",
        "create_supply_set", "associate_supply_set", "add_power_state",
        "set_partial_on_translation", "set_retention"})
    commands.push_back({&session, name});
  for (auto &command : commands)
    Tcl_CreateObjCommand2(interp.get(), command.name, dispatch, &command,
                          nullptr);
  // Delete the interpreter while command client data and its design context
  // are still alive (command-deletion traces may execute Tcl).
  auto cleanup = llvm::scope_exit([&] { interp.reset(); });
  for (auto &path : paths) {
    session.file = path;
    if (Tcl_EvalFile(interp.get(), path.c_str()) != TCL_OK) {
      const char *details =
          Tcl_GetVar(interp.get(), "errorInfo", TCL_GLOBAL_ONLY);
      return emitError(FileLineColLoc::get(module.getContext(), path,
                                           Tcl_GetErrorLine(interp.get()), 1))
             << "UPF execution failed: "
             << (details ? details : Tcl_GetStringResult(interp.get()));
    }
  }
  if (session.partialOnTranslation)
    module->setAttr(upf::partialOnTranslationName,
                    upf::PartialOnTranslationAttr::get(
                        module.getContext(), *session.partialOnTranslation));
  for (auto &[name, domain] : session.domains)
    if (!domain.composite && !domain.hasElements)
      return emitError(domain.location.value_or(module.getLoc()))
             << "power domain requires -elements in its base or an update "
                "(IEEE 1801-2018 6.20): "
             << name;
  // 8.3.2: a base strategy may be completed by later -update calls, including
  // in another UPF file. Diagnose incompleteness only after all Tcl executes.
  for (auto &[domainName, domain] : session.domains)
    for (auto &[name, retention] : domain.retentions)
      if (!retention.noRetention && !retention.save && !retention.restore &&
          !retention.condition)
        return emitError(retention.location.value_or(module.getLoc()))
               << "retention requires a save/restore signal or retention "
                  "condition (IEEE 1801-2018 6.50)";
  SupplyFunctions functions;
  SupplyEquivalences equivalences;
  for (auto &[name, set] : session.supplySets) {
    for (StringRef function : upf::getSupplyFunctionNames())
      functions[name + "." + function.str()] = set.scope;
    for (auto &[function, object] : set.functions)
      equivalences.emplace_back(session.function(name, function), object);
  }
  for (auto &[a, b] : session.setAssociations)
    for (StringRef function : upf::getSupplyFunctionNames())
      equivalences.emplace_back(session.function(a, function),
                                session.function(b, function));
  for (auto &[name, domain] : session.domains)
    if (assumePoweredInputs && domain.outputSupply && !domain.primaryAssociated)
      // Preserve the old primary-output inference only in compatibility mode.
      equivalences.emplace_back(session.function(domain.primary, "power"),
                                *domain.outputSupply);
  std::string supplyError;
  auto resolved = resolveSupplies(
      session.nets, session.supplyPortInfo, functions, session.supplyBindings,
      equivalences,
      [&](const llvm::Twine &message) { supplyError = message.str(); });
  if (failed(resolved))
    return module.emitError() << supplyError;
  // 4.5.4.7/4.5.5.3: binding an unused function does not make it required.
  // Propagate usage through existing explicit associations before testing
  // natural equivalence of composite primaries. Keep catalog provenance out
  // of the new physical propagation links (6.16).
  if (llvm::any_of(session.domains,
                   [](const auto &entry) { return entry.second.composite; })) {
    // Always check constraints against the topology before composition. A
    // later usage iteration must not bless rails merged by an earlier one.
    auto initial = *resolved;
    auto originalEquivalences = equivalences;
    bool first = true;
    while (true) {
      bool added = false;
      for (auto &[name, set] : session.supplySets)
        for (auto &[stateName, state] : set.states)
          if (state.condition)
            for (auto &token : state.condition->tokens) {
              if (!token.reference || !token.reference->function.empty())
                continue;
              auto &object = token.reference->object;
              unsigned root = object.kind == SupplyObject::Net
                                  ? resolved->nets.at(object.path)
                              : object.kind == SupplyObject::Port
                                  ? resolved->ports.at(object.path)
                                  : resolved->functions.at(object.path);
              for (StringRef function : upf::getSupplyFunctionNames())
                if (root == resolved->functions.at(name + "." + function.str()))
                  added |= set.required.insert(function.str()).second;
            }
      bool requirementsChanged;
      do {
        requirementsChanged = false;
        for (auto &[a, b] : session.setAssociations) {
          auto &left = session.supplySets.at(a).required;
          auto &right = session.supplySets.at(b).required;
          for (auto function : left)
            requirementsChanged |= right.insert(function).second;
          for (auto function : right)
            requirementsChanged |= left.insert(function).second;
        }
        added |= requirementsChanged;
      } while (requirementsChanged);
      if (!first && !added)
        break;
      first = false;
      llvm::IntEqClasses composition(initial.roots.size());
      std::vector<std::optional<unsigned>> constrained(initial.roots.size());
      for (auto [index, root] : llvm::enumerate(initial.roots))
        if (root.explicitSource)
          constrained[index] = index;
      SupplyEquivalences compositionLinks;
      for (auto &[name, domain] : session.domains) {
        if (!domain.composite)
          continue;
        auto &primary = session.supplySets.at(domain.primary);
        for (auto &childName : domain.subdomains) {
          auto &child = session.domains.at(childName);
          auto &childPrimary = session.supplySets.at(child.primary);
          if (primary.required != childPrimary.required)
            return emitError(domain.location.value_or(module.getLoc()))
                   << "composite primary supplies with different required "
                      "functions "
                      "are not implemented (IEEE 1801-2018 4.5.5.3/6.16): "
                   << childName;
          for (auto &function : primary.required) {
            unsigned a = composition.findLeader(
                initial.functions.at(domain.primary + "." + function));
            unsigned b = composition.findLeader(
                initial.functions.at(child.primary + "." + function));
            if (a != b && constrained[a] && constrained[b])
              return emitError(domain.location.value_or(module.getLoc()))
                     << "composite primary supplies are not electrically "
                        "equivalent "
                        "(IEEE 1801-2018 6.16): "
                     << name << " and " << childName << " function "
                     << function;
            std::optional<unsigned> source =
                constrained[a] ? constrained[a] : constrained[b];
            constrained[composition.join(a, b)] = source;
            compositionLinks.emplace_back(
                session.function(domain.primary, function),
                session.function(child.primary, function));
          }
        }
      }
      if (!compositionLinks.empty()) {
        equivalences = originalEquivalences;
        equivalences.insert(equivalences.end(), compositionLinks.begin(),
                            compositionLinks.end());
        resolved = resolveSupplies(
            session.nets, session.supplyPortInfo, functions,
            session.supplyBindings, equivalences,
            [&](const llvm::Twine &message) { supplyError = message.str(); });
        if (failed(resolved))
          return module.emitError() << supplyError;
      }
    }
  }
  auto &supplies = *resolved;
  auto rootFor = [&](const SupplyObject &object) {
    if (object.kind == SupplyObject::Function)
      return supplies.functions.at(object.path);
    if (object.kind == SupplyObject::Port)
      return supplies.ports.at(object.path);
    return supplies.nets.at(object.path);
  };
  for (auto &[name, set] : session.supplySets)
    for (auto &[stateName, state] : set.states) {
      if (!state.condition)
        continue;
      if (state.simstate == upf::Simstate::Unspecified)
        return emitError(state.location.value_or(
                   set.location.value_or(module.getLoc())))
               << "active power states without a simstate require history "
                  "semantics and are not implemented: "
               << stateName;
      bool powerOrGround = false;
      // Later bindings can make previously independent references equivalent.
      // Recheck 5.10/6.5.2 after resolving the final supply topology.
      auto contradiction = contradictsSupplyExpression(
          *state.condition, [&](const SupplyObject &a, const SupplyObject &b) {
            return rootFor(a) == rootFor(b);
          });
      if (!contradiction || *contradiction)
        return emitError(state.location.value_or(
                   set.location.value_or(module.getLoc())))
               << (!contradiction ? "supply-expression consistency check "
                                    "exceeds 256 branches or 65536 work units"
                                  : "contradictory supply expression (IEEE "
                                    "1801-2018 5.10/6.5.2)");
      for (auto &token : state.condition->tokens)
        if (token.reference) {
          const auto &reference = *token.reference;
          if (!reference.function.empty()) {
            powerOrGround |=
                reference.function == "power" || reference.function == "ground";
          } else {
            for (StringRef function : upf::getSupplyFunctionNames())
              if (rootFor(reference.object) ==
                  supplies.functions.at(name + "." + function.str())) {
                set.required.insert(function.str());
                powerOrGround |= function == "power" || function == "ground";
              }
          }
        }
      if (!powerOrGround)
        return emitError(state.location.value_or(
                   set.location.value_or(module.getLoc())))
               << "supply expression must reference the set's power or ground "
                  "function (IEEE 1801-2018 6.5.6a)";
    }
  bool changed;
  do {
    changed = false;
    for (auto &[a, b] : session.setAssociations) {
      auto &left = session.supplySets.at(a).required;
      auto &right = session.supplySets.at(b).required;
      for (auto function : left)
        changed |= right.insert(function).second;
      for (auto function : right)
        changed |= left.insert(function).second;
    }
  } while (changed);
  for (auto &[name, set] : session.supplySets)
    supplies.roots[supplies.functions.at(name + ".ground")].ground = true;
  struct DomainSupplies {
    unsigned power, ground;
    std::optional<unsigned> input;
  };
  std::map<std::string, DomainSupplies> domainSupplies;
  for (auto &[name, domain] : session.domains) {
    if (domain.composite)
      continue;
    unsigned power = supplies.functions.at(domain.primary + ".power");
    unsigned ground = supplies.functions.at(domain.primary + ".ground");
    std::optional<unsigned> input;
    if (!domain.switchOutput.empty()) {
      input = rootFor(*domain.inputSupply);
      unsigned output = supplies.ports.at(domain.outputPort);
      if (power != output) {
        if (!domain.primaryAssociated)
          return emitError(domain.location.value_or(module.getLoc()))
                 << "switchable domain requires an explicit primary supply "
                    "association with set_domain_supply_net (IEEE 1801-2018 "
                    "6.22/6.43)";
        return emitError(domain.location.value_or(module.getLoc()))
               << "switch output does not drive the domain primary supply";
      }
      if (*input == output)
        return emitError(domain.location.value_or(module.getLoc()))
               << "power-switch input and output are electrically connected";
      if (!supplies.roots[*input].writable)
        return emitError(domain.location.value_or(module.getLoc()))
               << "cascaded power switches are not implemented";
    } else if (!supplies.roots[power].writable) {
      return emitError(domain.location.value_or(module.getLoc()))
             << "sharing a switched supply across power domains is not "
                "implemented";
    }
    if (!supplies.roots[ground].writable)
      return emitError(domain.location.value_or(module.getLoc()))
             << "switched primary ground is not implemented";
    domainSupplies.emplace(name, DomainSupplies{power, ground, input});
  }
  OpBuilder builder(module.getContext());
  builder.setInsertionPointToEnd(module.getBody());
  auto supplySymbol = [&](unsigned id) {
    return FlatSymbolRefAttr::get(module.getContext(),
                                  "__upf_supply_" + std::to_string(id));
  };
  auto expressionAttr = [&](const SupplyExpression &expression) {
    SmallVector<Attribute> tokens;
    for (auto &token : expression.tokens) {
      FlatSymbolRefAttr supply;
      StringAttr function;
      IntegerAttr value;
      FloatAttr real;
      if (token.reference) {
        supply = supplySymbol(rootFor(token.reference->object));
        if (!token.reference->function.empty())
          function = builder.getStringAttr(token.reference->function);
      }
      using O = upf::SupplyExpressionOpcode;
      if (token.opcode == O::Boolean)
        value = builder.getIntegerAttr(builder.getI1Type(), token.value);
      if (token.opcode == O::StateValue)
        value = builder.getI32IntegerAttr(token.value);
      if (token.opcode == O::Real)
        real = builder.getF64FloatAttr(token.real);
      tokens.push_back(upf::SupplyExpressionTokenAttr::get(
          module.getContext(), token.opcode, supply, function, value, real));
    }
    return upf::SupplyExpressionAttr::get(module.getContext(),
                                          builder.getArrayAttr(tokens));
  };
  std::map<std::string, std::set<std::string>> associated;
  for (auto &[a, b] : session.setAssociations) {
    if (a == b)
      continue;
    associated[a].insert(b);
    associated[b].insert(a);
  }
  std::set<unsigned> anonymousRoots;
  for (auto &[domainName, domain] : session.domains)
    for (auto &[name, retention] : domain.retentions) {
      auto &handle = session.supplySets.at(retention.retentionSupply);
      if (!handle.functions.empty() || handle.explicitStrategySupply)
        continue;
      // 6.10: list-form association to a named supplying set is equivalent
      // electrically to -handle binding. A domain primary or another strategy
      // handle can instead be a downstream consumer of this assumed source.
      std::vector<std::string> work{retention.retentionSupply};
      std::set<std::string> seen;
      bool namedSupplier = false;
      while (!work.empty()) {
        std::string current = std::move(work.back());
        work.pop_back();
        if (!seen.insert(current).second)
          continue;
        namedSupplier |= !session.supplySets.at(current).handle;
        for (auto &next : associated[current])
          work.push_back(next);
      }
      if (namedSupplier)
        continue;
      std::set<unsigned> roots;
      for (StringRef function : upf::getSupplyFunctionNames())
        roots.insert(supplies.functions.at(retention.retentionSupply + "." +
                                           function.str()));
      if (llvm::any_of(roots, [&](unsigned root) {
            return supplies.roots[root].explicitSource;
          }))
        continue;
      // 6.50/9.7.1: an unspecified verification retention supply is anonymous
      // and always on. It has real shared values, so queries and policy
      // evaluation agree; HDL cannot turn this assumed supply off.
      anonymousRoots.insert(roots.begin(), roots.end());
      for (unsigned root : roots)
        supplies.roots[root].writable = false;
    }
  // Internal 6.43 suppliers contribute policy, but no additional public HDL
  // supply names or runtime lookups. Every function is associated with the
  // existing primary function, so it also introduces no physical supply root.
  std::set<std::string> privateSupplyNames;
  for (auto &[name, set] : session.supplySets)
    if (set.privateSupplier)
      for (StringRef function : upf::getSupplyFunctionNames()) {
        std::string handle = name + "." + function.str();
        privateSupplyNames.insert(handle);
        privateSupplyNames.insert(handle + "@upfSupplyNetT");
      }
  for (unsigned id = 0; id < supplies.roots.size(); ++id) {
    SmallVector<Attribute> names;
    for (auto &[name, root] : supplies.handles)
      if (root == id && !privateSupplyNames.count(name))
        names.push_back(builder.getStringAttr(name));
    auto root = supplies.roots[id];
    // Standard initialization is OFF, unspecified voltage (9.2.1). The old
    // FULL_ON-input prototype requires explicit compatibility mode.
    uint64_t initial =
        anonymousRoots.count(id) || (assumePoweredInputs && root.writable)
            ? ((uint64_t(root.ground ? 0 : 1000000) << 2) | 1)
            : 0;
    upf::UPFSupplyOp::create(builder, module.getLoc(),
                             supplySymbol(id).getValue(),
                             builder.getArrayAttr(names), root.writable,
                             initial, anonymousRoots.count(id));
  }
  for (auto &[name, set] : session.supplySets) {
    NamedAttrList bindings;
    SmallVector<Attribute> required;
    for (StringRef function : upf::getSupplyFunctionNames())
      bindings.set(function, supplySymbol(supplies.functions.at(
                                 name + "." + function.str())));
    for (auto &function : set.required)
      required.push_back(builder.getStringAttr(function));
    SmallVector<Attribute> states, links;
    for (auto &[stateName, state] : set.states)
      states.push_back(upf::PowerStateAttr::get(
          module.getContext(), builder.getStringAttr(stateName),
          state.condition ? expressionAttr(*state.condition)
                          : upf::SupplyExpressionAttr{},
          state.simstate, state.illegal));
    for (auto &other : associated[name])
      links.push_back(FlatSymbolRefAttr::get(module.getContext(), other));
    auto declaration = upf::UPFSupplySetOp::create(
        builder, set.location.value_or(module.getLoc()), name,
        bindings.getDictionary(module.getContext()),
        builder.getArrayAttr(required),
        states.empty() ? ArrayAttr{} : builder.getArrayAttr(states),
        links.empty() ? ArrayAttr{} : builder.getArrayAttr(links),
        set.owner.empty()
            ? FlatSymbolRefAttr{}
            : FlatSymbolRefAttr::get(module.getContext(), set.owner),
        set.complete,
        set.strategy.empty() ? StringAttr{}
                             : builder.getStringAttr(set.strategy),
        set.binding.empty()
            ? FlatSymbolRefAttr{}
            : FlatSymbolRefAttr::get(module.getContext(), set.binding));
    if (set.privateSupplier)
      SymbolTable::setSymbolVisibility(declaration,
                                       SymbolTable::Visibility::Private);
  }
  for (auto &[name, domain] : session.domains) {
    if (domain.composite) {
      SmallVector<Attribute> children;
      for (auto &child : domain.subdomains)
        children.push_back(FlatSymbolRefAttr::get(module.getContext(), child));
      upf::UPFCompositeDomainOp::create(
          builder, domain.location.value_or(module.getLoc()),
          builder.getStringAttr(name),
          builder.getArrayAttr(children),
          FlatSymbolRefAttr::get(module.getContext(), domain.primary));
      continue;
    }
    llvm::SmallVector<Attribute> elements, excluded;
    for (auto &element : domain.elements)
      elements.push_back(builder.getStringAttr(element));
    for (auto &element : domain.excluded)
      excluded.push_back(builder.getStringAttr(element));
    // 6.20/9.5.1: retain role provenance. Global supply sets associated to
    // this primary can constrain its elements; a sibling domain's local
    // primary catalog does not acquire that role merely by sharing rails.
    std::vector<std::string> work{domain.primary};
    std::set<std::string> seen;
    SmallVector<Attribute> policies;
    while (!work.empty()) {
      auto id = std::move(work.back());
      work.pop_back();
      if (!seen.insert(id).second)
        continue;
      auto &view = session.supplySets.at(id);
      bool otherPrimary = !view.owner.empty() &&
                          session.domains.at(view.owner).primary == id &&
                          id != domain.primary;
      if (!otherPrimary && view.strategy.empty())
        policies.push_back(FlatSymbolRefAttr::get(module.getContext(), id));
      for (auto &next : associated[id])
        work.push_back(next);
    }
    SmallVector<Attribute> retentions;
    for (auto &[strategyName, retention] : domain.retentions) {
      auto selectors = [&](const auto &entries) {
        SmallVector<Attribute> result;
        for (auto &[path, attr] : entries)
          result.push_back(attr);
        return builder.getArrayAttr(result);
      };
      retentions.push_back(upf::RetentionAttr::get(
          module.getContext(), builder.getStringAttr(strategyName),
          builder.getStringAttr(retention.scope), selectors(retention.elements),
          selectors(retention.excluded),
          FlatSymbolRefAttr::get(module.getContext(),
                                 retention.retentionSupply),
          FlatSymbolRefAttr::get(module.getContext(), retention.primarySupply),
          !retention.hasElements, retention.noRetention, retention.save,
          retention.restore, retention.saveCondition,
          retention.restoreCondition, retention.condition,
          retention.location ? mlir::LocationAttr(*retention.location)
                             : mlir::LocationAttr{},
          retention.useRetentionAsPrimary,
          retention.retentionSupplyCorrupt.value_or(true),
          retention.saveRestoreCorrupt.value_or(true)));
    }
    upf::UPFDomainOp::create(
        builder, domain.location.value_or(module.getLoc()), name,
        builder.getArrayAttr(elements),
        supplySymbol(domainSupplies.at(name).power).getValue(),
        supplySymbol(domainSupplies.at(name).ground),
        domainSupplies.at(name).input
            ? supplySymbol(*domainSupplies.at(name).input)
            : FlatSymbolRefAttr{},
        FlatSymbolRefAttr::get(module.getContext(), domain.primary),
        builder.getArrayAttr(policies), builder.getArrayAttr(domain.on),
        domain.partial.empty() ? ArrayAttr{}
                               : builder.getArrayAttr(domain.partial),
        domain.off,
        domain.errors.empty() ? ArrayAttr{}
                              : builder.getArrayAttr(domain.errors),
        domain.isolation.empty() ? StringAttr{}
                                 : builder.getStringAttr(domain.isolation),
        domain.isolationHigh, domain.clamp,
        retentions.empty() ? ArrayAttr{} : builder.getArrayAttr(retentions),
        domain.isolationName.empty()
            ? StringAttr{}
            : builder.getStringAttr(domain.isolationName),
        domain.isolationDiffSupplyOnly,
        excluded.empty() ? ArrayAttr{} : builder.getArrayAttr(excluded),
        upf::DomainExtentAttr{}, domain.atomic);
  }
  if (failed(resolveUPFDomainExtents(module)))
    return failure();
  return verify(module);
#endif
}
} // namespace talos
