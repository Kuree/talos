// Tcl executes the language; this file implements UPF commands and design
// lookup.
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
  std::string name, scope, power, switchOutput, control, isolation;
  std::vector<std::string> elements;
  bool onHigh = true, isolationHigh = true;
  int64_t clamp = 0;
  bool primaryAssociated = false;
  std::optional<Location> location;
};
struct Session {
  ModuleOp module;
  Tcl_Interp *interp;
  std::string top, scope, file, designModule;
  std::map<std::string, Operation *> objects;
  std::map<std::string, Domain> domains;
  std::set<std::string> nets, supplyPorts, switches;
  std::set<std::string> designPorts;
  Session(ModuleOp module, Tcl_Interp *interp)
      : module(module), interp(interp) {
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
  bool options(Tcl_Size objc, Tcl_Obj *const objv[], Tcl_Size first,
               std::initializer_list<StringRef> allowed, Options &out) {
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
  bool control(StringRef path, std::string &out) {
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
    return true;
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
      for (auto &port : ports)
        if (!supplyPorts.count(key(port)))
          return error("unknown supply port: " + port);
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
      found->second.primaryAssociated = true;
      Tcl_SetObjResult(interp, Tcl_NewIntObj(1));
      return TCL_OK;
    }
    if (command == "create_power_switch") {
      // IEEE 1801-2018 6.22: -domain uses the owning domain's scope, and
      // control expressions reference the switch's declared control-port names.
      if (objc < 2 ||
          !options(objc, objv, 2,
                   {"-domain", "-input_supply_port", "-output_supply_port",
                    "-control_port", "-on_state", "-off_state"},
                   opts))
        return TCL_ERROR;
      Domain *dom = domain(opts);
      if (!dom)
        return TCL_ERROR;
      if (!identifier(Tcl_GetString(objv[1])))
        return TCL_ERROR;
      std::string previousScope = scope;
      auto restoreScope = llvm::scope_exit([&] { scope = previousScope; });
      scope = dom->scope;
      if (!dom->control.empty())
        return error("one power switch per domain is supported");
      std::vector<std::string> input, output, controlPort, on, off;
      for (StringRef required : {"-input_supply_port", "-output_supply_port",
                                 "-control_port", "-on_state"})
        if (!opts.count(required.str()))
          return error("missing power-switch option " + required);
      if (!list(opts["-input_supply_port"], input) ||
          !list(opts["-output_supply_port"], output) ||
          !list(opts["-control_port"], controlPort) ||
          !list(opts["-on_state"], on))
        return TCL_ERROR;
      if (input.size() != 2 || output.size() != 2 || controlPort.size() != 2 ||
          on.size() != 3)
        return error("expected single input/output supply, control port, and "
                     "on-state expression");
      if (!nets.count(key(input[1])) || !nets.count(key(output[1])))
        return error("power switch references an unknown supply net");
      if (key(input[1]) == key(output[1]))
        return error("a switch must have distinct input and output supplies");
      if (on[1] != input[0])
        return error("on-state references an unknown input supply port");
      StringRef expression = StringRef(on[2]).trim();
      bool onHigh = !expression.consume_front("!");
      expression = expression.trim();
      if (expression != controlPort[0])
        return error(
            "on-state currently requires one control port, optionally negated");
      std::string resolvedControl;
      if (!control(controlPort[1], resolvedControl))
        return TCL_ERROR;
      if (opts.count("-off_state")) {
        if (!list(opts["-off_state"], off))
          return TCL_ERROR;
        if (off.size() != 2 ||
            StringRef(off[1]).trim() !=
                (onHigh ? "!" + controlPort[0] : controlPort[0]))
          return error("off-state must complement the on-state control");
      }
      if (!dom->power.empty() && dom->power != key(output[1]))
        return error("switch output does not drive the domain primary supply");
      if (!switches.insert(key(Tcl_GetString(objv[1]))).second)
        return error("duplicate power switch");
      dom->onHigh = onHigh;
      dom->control = resolvedControl;
      dom->power = dom->switchOutput = key(output[1]);
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
                         StringRef resourceDir, StringRef executablePath) {
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
  Session session(module, interp.get());
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
  OpBuilder builder(module.getContext());
  builder.setInsertionPointToEnd(module.getBody());
  for (auto &[name, domain] : session.domains) {
    if (domain.control.empty()) {
      if (!domain.isolation.empty())
        return module.emitError(
            "initial UPF isolation requires a switchable domain");
      continue;
    }
    if (domain.power != domain.switchOutput)
      return module.emitError(
          "power-switch output does not match the domain primary supply");
    llvm::SmallVector<Attribute> elements;
    for (auto &element : domain.elements)
      elements.push_back(builder.getStringAttr(element));
    upf::UPFDomainOp::create(
        builder, domain.location.value_or(module.getLoc()), name,
        builder.getArrayAttr(elements), domain.control, domain.onHigh,
        domain.isolation.empty() ? StringAttr{}
                                 : builder.getStringAttr(domain.isolation),
        domain.isolationHigh, domain.clamp);
  }
  return verify(module);
#endif
}
} // namespace talos
