// Tcl executes the language; this file implements UPF commands and design
// lookup.
#include "BooleanExpression.h"
#include "ControlReference.h"
#include "SupplyNetwork.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Verifier.h"
#include "talos/Dialect/Slang/SlangOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <vector>
#ifdef TALOS_ENABLE_UPF
#include <tcl.h>
#endif
using namespace mlir;
using llvm::StringRef;
namespace talos {
#ifdef TALOS_ENABLE_UPF
namespace {
struct Domain {
  std::string name, scope, power, ground, switchInput, switchOutput, isolation;
  std::string inputPort, outputPort;
  SmallVector<Attribute> on, errors;
  upf::SwitchStateAttr off;
  std::vector<std::string> elements;
  bool isolationHigh = true;
  int64_t clamp = 0;
  bool primaryAssociated = false;
  std::optional<Location> location;
};
struct Session {
  ModuleOp module;
  Tcl_Interp *interp;
  bool allowHDLExpressions;
  std::string top, scope, file, designModule;
  std::map<std::string, Operation *> objects;
  std::map<std::string, Domain> domains;
  std::set<std::string> nets, supplyPorts, switches;
  SupplyPorts supplyPortInfo;
  SupplyBindings supplyBindings;
  std::set<std::string> designPorts;
  Session(ModuleOp module, Tcl_Interp *interp, bool allowHDLExpressions)
      : module(module), interp(interp),
        allowHDLExpressions(allowHDLExpressions) {
    std::set<std::string> tops;
    module.walk([&](Operation *op) {
      auto path = op->getAttrOfType<StringAttr>("hierarchical_name");
      StringRef kind = op->getName().getStringRef();
      if (!path ||
          (kind != "slang.symbol.instance" && kind != "slang.symbol.variable" &&
           kind != "slang.symbol.net" && kind != "slang.symbol.port"))
        return;
      if (kind != "slang.symbol.port" || !objects.count(path.str()))
        objects[path.str()] = op;
      if (kind == "slang.symbol.port")
        designPorts.insert(path.str());
      if (op->getName().getStringRef() == "slang.symbol.instance" &&
          !path.getValue().contains('.')) {
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
    if (path == top)
      return "/";
    StringRef suffix = path.drop_front(top.size() + 1);
    std::string result = "/" + suffix.str();
    for (char &ch : result)
      if (ch == '.')
        ch = '/';
    return result;
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
    std::string result = resolve(name);
    if (objects.count(result))
      return result;
    return {};
  }
  std::string key(StringRef name) const { return resolve(name); }
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
               RepeatedOptions *repeated = nullptr) {
    for (Tcl_Size i = first; i < objc; ++i) {
      StringRef option = Tcl_GetString(objv[i]);
      if (!llvm::is_contained(allowed, option)) {
        error("unsupported UPF option '" + option + "' in " +
              Tcl_GetString(objv[0]));
        return false;
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
  Domain *domain(const Options &options) {
    auto found = domains.find(key(value(options, "-domain")));
    if (found == domains.end()) {
      error("unknown power domain '" + value(options, "-domain") + "'");
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
  int run(StringRef command, Tcl_Size objc, Tcl_Obj *const objv[]) {
    Options opts;
    // IEEE 1801-2018 5.11: command failures are Tcl errors, so catch/proc
    // libraries observe the same error path as direct command invocations.
    if (objc < 2 && command != "upf_version")
      return error("missing argument for " + command);
    if (command == "upf_version") {
      if (objc > 2 || (objc == 2 && StringRef(Tcl_GetString(objv[1])) != "3.1"))
        return error(
            "this UPF frontend targets IEEE 1801-2018 (upf_version 3.1)");
      Tcl_SetObjResult(interp, Tcl_NewStringObj("3.1", -1));
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
        scope = scope.substr(0, scope.rfind('.'));
      } else {
        std::string next = object(requested);
        if (next.empty() || objects.at(next)->getName().getStringRef() !=
                                "slang.symbol.instance")
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
    if (command == "find_objects") {
      // IEEE 1801-2018 6.31.1: default non-transitive; a bare -transitive
      // means TRUE; every returned object is relative to the current scope.
      bool transitive = false, sawTransitive = false;
      for (Tcl_Size i = 2; i < objc; ++i) {
        StringRef option = Tcl_GetString(objv[i]);
        if (option == "-transitive") {
          if (sawTransitive)
            return error("duplicate UPF option -transitive");
          sawTransitive = transitive = true;
          if (i + 1 < objc &&
              !StringRef(Tcl_GetString(objv[i + 1])).starts_with('-')) {
            int flag;
            if (Tcl_GetBooleanFromObj(interp, objv[++i], &flag) != TCL_OK)
              return TCL_ERROR;
            transitive = flag;
          }
        } else {
          if (option != "-pattern" && option != "-object_type")
            return error("unsupported find_objects option: " + option);
          if (++i == objc)
            return error("missing value for " + option);
          if (!opts.emplace(option.str(), objv[i]).second)
            return error("duplicate UPF option " + option);
        }
      }
      StringRef requestedScope = Tcl_GetString(objv[1]);
      if (requestedScope.starts_with('/') || requestedScope.starts_with(".."))
        return error("find_objects scope must be relative to current scope");
      std::string base = object(requestedScope);
      if (base.empty() ||
          objects.at(base)->getName().getStringRef() !=
              "slang.symbol.instance" ||
          (base != scope && !StringRef(base).starts_with(scope + ".")))
        return error("find_objects scope not found");
      StringRef pattern = value(opts, "-pattern");
      if (!opts.count("-pattern"))
        return error("find_objects requires -pattern");
      // IEEE 1801-2018 6.31.2 also defines brace alternatives, which Tcl's
      // StringMatch does not implement. Diagnose that deferred pattern form.
      if (pattern.contains('{') || pattern.contains('}'))
        return error("find_objects brace alternatives are not implemented");
      StringRef kind = value(opts, "-object_type");
      if (!kind.empty() && kind != "inst" && kind != "port" && kind != "net")
        return error("unsupported find_objects object type: " + kind);
      Tcl_Obj *result = Tcl_NewListObj(0, nullptr);
      for (auto &[path, operation] : objects) {
        StringRef relative = path;
        if (!relative.consume_front(base + "."))
          continue;
        StringRef op = operation->getName().getStringRef();
        if ((kind == "inst" && op != "slang.symbol.instance") ||
            (kind == "port" && !designPorts.count(path)) ||
            (kind == "net" && op != "slang.symbol.net") ||
            (kind.empty() && op != "slang.symbol.instance" &&
             op != "slang.symbol.net" && !designPorts.count(path)))
          continue;
        // Match individual hierarchy components: Tcl '*' must not cross '/'.
        llvm::SmallVector<StringRef> names, patterns;
        relative.split(names, '.');
        pattern.split(patterns, '/');
        bool match = names.size() >= patterns.size() &&
                     (transitive || names.size() == patterns.size());
        if (match) {
          size_t offset = names.size() - patterns.size();
          for (size_t i = 0; i < patterns.size(); ++i)
            match &= Tcl_StringMatch(names[offset + i].str().c_str(),
                                     patterns[i].str().c_str());
        }
        if (!match)
          continue;
        std::string resultName = path.substr(scope.size() + 1);
        for (char &ch : resultName)
          if (ch == '.')
            ch = '/';
        Tcl_ListObjAppendElement(interp, result,
                                 Tcl_NewStringObj(resultName.c_str(), -1));
      }
      Tcl_SetObjResult(interp, result);
      return TCL_OK;
    }
    if (command == "create_power_domain") {
      if (objc < 2 || !options(objc, objv, 2, {"-elements"}, opts))
        return TCL_ERROR;
      Domain dom;
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      dom.location = declarationLocation();
      dom.name = key(Tcl_GetString(objv[1]));
      dom.scope = scope;
      std::vector<std::string> names;
      // IEEE 1801-2018 6.20: omitted -elements creates an empty extent,
      // not an implicit '.'. Empty/updateable domains are a deferred feature.
      if (!opts.count("-elements"))
        return error("initial power domains require explicit -elements");
      if (!list(opts["-elements"], names))
        return TCL_ERROR;
      for (auto &name : names) {
        std::string path = object(name);
        if (path.empty() || objects.at(path)->getName().getStringRef() !=
                                "slang.symbol.instance")
          return error("power-domain element is not a design instance: " +
                       name);
        dom.elements.push_back(path);
      }
      if (dom.elements.empty())
        return error("power domain has no elements");
      if (!domains.emplace(dom.name, std::move(dom)).second)
        return error("duplicate power domain");
      return TCL_OK;
    }
    if (command == "create_supply_net" || command == "create_supply_port") {
      // IEEE 1801-2018 6.24.1/6.25: -domain selects the declaration scope.
      if (objc < 2)
        return error("supply declaration requires a name");
      if (command == "create_supply_net") {
        if (!options(objc, objv, 2, {"-domain", "-resolve"}, opts))
          return TCL_ERROR;
      } else if (!options(objc, objv, 2, {"-domain", "-direction"}, opts))
        return TCL_ERROR;
      StringRef direction = value(opts, "-direction");
      if (!direction.empty() && direction != "in" && direction != "out" &&
          direction != "inout")
        return error("supply-port direction must be in, out, or inout");
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      std::string previousScope = scope;
      auto restoreScope = llvm::scope_exit([&] { scope = previousScope; });
      if (opts.count("-domain")) {
        Domain *owner = domain(opts);
        if (!owner)
          return TCL_ERROR;
        scope = owner->scope;
      }
      if (opts.count("-resolve") && value(opts, "-resolve") != "unresolved")
        return error("the first UPF slice supports unresolved supply nets");
      auto &inventory = command == "create_supply_net" ? nets : supplyPorts;
      if (!inventory.insert(key(Tcl_GetString(objv[1]))).second)
        return error("duplicate supply object");
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
      if (!nets.count(key(Tcl_GetString(objv[1]))))
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
                key(Tcl_GetString(objv[1])), key(port), bindings,
                [&](const llvm::Twine &message) { error(message); })))
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
      if (!opts.count("-primary_power_net") ||
          !opts.count("-primary_ground_net"))
        return error("both primary power and ground nets are required");
      if (found->second.primaryAssociated)
        return error("domain primary supply is already associated");
      std::string previousScope = scope;
      auto restoreScope = llvm::scope_exit([&] { scope = previousScope; });
      scope = found->second.scope;
      for (auto &option : opts)
        if (!nets.count(key(Tcl_GetString(option.second))))
          return error("unknown primary supply net");
      found->second.power = key(value(opts, "-primary_power_net"));
      found->second.ground = key(value(opts, "-primary_ground_net"));
      found->second.primaryAssociated = true;
      Tcl_SetObjResult(interp, Tcl_NewIntObj(1));
      return TCL_OK;
    }
    if (command == "create_power_switch") {
      // IEEE 1801-2018 6.22: -domain uses the owning domain's scope, and
      // control expressions reference the switch's declared control-port names.
      RepeatedOptions repeated{
          {"-control_port", {}}, {"-on_state", {}}, {"-error_state", {}}};
      if (objc < 2 ||
          !options(objc, objv, 2,
                   {"-domain", "-input_supply_port", "-output_supply_port",
                    "-control_port", "-on_state", "-off_state", "-error_state"},
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
      if (!dom->switchOutput.empty())
        return error("one power switch per domain is supported");
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
      if (!nets.count(key(input[1])) || !nets.count(key(output[1])))
        return error("power switch references an unknown supply net");
      if (key(input[1]) == key(output[1]))
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
      SmallVector<Attribute> onStates, errorStates;
      for (auto obj : repeated["-on_state"]) {
        auto parsed = state(obj, true);
        if (failed(parsed))
          return TCL_ERROR;
        onStates.push_back(*parsed);
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
        if (other.switchOutput == key(output[1]))
          return error(
              "multiple switches drive the same unresolved supply net");
        if (other.switchOutput == key(input[1]) ||
            other.switchInput == key(output[1]))
          return error("cascaded power switches are not implemented");
      }
      std::string switchName = key(Tcl_GetString(objv[1]));
      std::string inputPort = switchName + "." + input[0];
      std::string outputPort = switchName + "." + output[0];
      if (supplyPorts.count(inputPort) || supplyPorts.count(outputPort))
        return error("power-switch supply port already exists");
      auto bindings = supplyBindings;
      for (auto [net, port] : {std::make_pair(key(input[1]), inputPort),
                               std::make_pair(key(output[1]), outputPort)})
        if (failed(bindSupply(
                net, port, bindings,
                [&](const llvm::Twine &message) { error(message); })))
          return TCL_ERROR;
      if (!switches.insert(switchName).second)
        return error("duplicate power switch");
      dom->on = std::move(onStates);
      dom->off = offState;
      dom->errors = std::move(errorStates);
      dom->switchInput = key(input[1]);
      dom->switchOutput = key(output[1]);
      // Legacy inference is used only by --upf-assume-powered-inputs. In
      // standard mode the final inventory requires an explicit association:
      // 6.22 -domain selects scope, not the primary supply function (6.43).
      if (dom->power.empty())
        dom->power = dom->switchOutput;
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
      if (objc < 2 ||
          !options(objc, objv, 2,
                   {"-domain", "-isolation_signal", "-isolation_sense",
                    "-clamp_value", "-applies_to", "-location"},
                   opts))
        return TCL_ERROR;
      Domain *dom = domain(opts);
      if (!dom)
        return TCL_ERROR;
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      if (!dom->isolation.empty())
        return error("one isolation strategy per domain is supported");
      if (value(opts, "-applies_to") != "outputs" ||
          value(opts, "-location") != "parent")
        return error("initial isolation support requires -applies_to outputs "
                     "-location parent");
      if (scope != dom->scope)
        return error(
            "initial isolation must be declared in the power domain's scope");
      std::string isolation;
      if (!control(value(opts, "-isolation_signal"), isolation))
        return TCL_ERROR;
      StringRef sense = value(opts, "-isolation_sense");
      if (!sense.empty() && sense != "high" && sense != "low")
        return error("isolation sense must be high or low");
      StringRef clamp = value(opts, "-clamp_value");
      if (clamp != "0" && clamp != "1")
        return error("initial isolation clamp must be 0 or 1");
      dom->isolation = isolation;
      dom->isolationHigh = sense != "low";
      dom->clamp = clamp == "1";
      return TCL_OK;
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
        "load_upf", "create_power_domain", "create_supply_net",
        "create_supply_port", "connect_supply_net", "set_domain_supply_net",
        "create_power_switch", "set_isolation"})
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
  std::string supplyError;
  auto resolved = resolveSupplies(
      session.nets, session.supplyPortInfo, session.supplyBindings,
      [&](const llvm::Twine &message) { supplyError = message.str(); });
  if (failed(resolved))
    return module.emitError() << supplyError;
  auto &supplies = *resolved;
  struct DomainSupplies {
    unsigned power, ground;
    std::optional<unsigned> input;
  };
  std::map<std::string, DomainSupplies> domainSupplies;
  for (auto &[name, domain] : session.domains) {
    auto root = [&](const std::string &net) {
      if (!net.empty())
        return supplies.nets.at(net);
      unsigned id = supplies.roots.size();
      supplies.roots.push_back({});
      return id;
    };
    unsigned power = root(domain.power), ground = root(domain.ground);
    supplies.roots[ground].ground = true;
    std::optional<unsigned> input;
    if (!domain.switchOutput.empty()) {
      if (!domain.primaryAssociated && !assumePoweredInputs)
        return emitError(domain.location.value_or(module.getLoc()))
               << "switchable domain requires an explicit primary supply "
                  "association with set_domain_supply_net (IEEE 1801-2018 "
                  "6.22/6.43)";
      input = supplies.nets.at(domain.switchInput);
      unsigned output = supplies.ports.at(domain.outputPort);
      if (power != output)
        return emitError(domain.location.value_or(module.getLoc()))
               << "switch output does not drive the domain primary supply";
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
    // IEEE 1801-2018 6.20/9.2.1/9.3.1: implicit primary functions have root
    // drivers unless associated with a network. HDL handles use absolute UPF
    // root paths, not Tcl design-relative '/' (11.2.3.1.1).
    std::string prefix =
        domain.scope.empty() ? "" : absoluteSupplyHandle(domain.scope);
    std::string simple =
        domain.scope.empty() ? name : name.substr(domain.scope.size() + 1);
    prefix += "/" + simple + ".primary.";
    supplies.handles[prefix + "power"] = power;
    supplies.handles[prefix + "ground"] = ground;
    domainSupplies.emplace(name, DomainSupplies{power, ground, input});
  }
  OpBuilder builder(module.getContext());
  builder.setInsertionPointToEnd(module.getBody());
  auto supplySymbol = [&](unsigned id) {
    return FlatSymbolRefAttr::get(module.getContext(),
                                  "__upf_supply_" + std::to_string(id));
  };
  for (unsigned id = 0; id < supplies.roots.size(); ++id) {
    SmallVector<Attribute> names;
    for (auto &[name, root] : supplies.handles)
      if (root == id)
        names.push_back(builder.getStringAttr(name));
    auto root = supplies.roots[id];
    // Standard initialization is OFF, unspecified voltage (9.2.1). The old
    // FULL_ON-input prototype requires explicit compatibility mode.
    uint64_t initial = assumePoweredInputs && root.writable
                           ? ((uint64_t(root.ground ? 0 : 1000000) << 2) | 1)
                           : 0;
    upf::UPFSupplyOp::create(
        builder, module.getLoc(), supplySymbol(id).getValue(),
        builder.getArrayAttr(names), root.writable, initial);
  }
  for (auto &[name, domain] : session.domains) {
    llvm::SmallVector<Attribute> elements;
    for (auto &element : domain.elements)
      elements.push_back(builder.getStringAttr(element));
    upf::UPFDomainOp::create(
        builder, domain.location.value_or(module.getLoc()), name,
        builder.getArrayAttr(elements),
        supplySymbol(domainSupplies.at(name).power).getValue(),
        supplySymbol(domainSupplies.at(name).ground),
        domainSupplies.at(name).input
            ? supplySymbol(*domainSupplies.at(name).input)
            : FlatSymbolRefAttr{},
        builder.getArrayAttr(domain.on), domain.off,
        domain.errors.empty() ? ArrayAttr{}
                              : builder.getArrayAttr(domain.errors),
        domain.isolation.empty() ? StringAttr{}
                                 : builder.getStringAttr(domain.isolation),
        domain.isolationHigh, domain.clamp);
  }
  return verify(module);
#endif
}
} // namespace talos
