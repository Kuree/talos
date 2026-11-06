#include "DesignQuery.h"
#ifdef TALOS_ENABLE_UPF
#include "talos/Dialect/Slang/SlangTypes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/StringSwitch.h"
#include <algorithm>
#include <limits>
#include <optional>
#include <set>

using namespace mlir;
using llvm::StringRef;
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

bool prefix(llvm::ArrayRef<std::string> path,
            llvm::ArrayRef<std::string> scope) {
  return path.size() >= scope.size() &&
         std::equal(scope.begin(), scope.end(), path.begin());
}

// UPF 5.3.5 escapes one following character, unlike an SV escaped identifier.
std::vector<std::string> splitUPF(StringRef spelling, bool pattern = false) {
  std::vector<std::string> result(1);
  bool characterClass = false;
  for (size_t i = 0; i < spelling.size(); ++i) {
    char ch = spelling[i];
    if (ch == '\\' && i + 1 < spelling.size()) {
      if (pattern)
        result.back() += ch;
      result.back() += spelling[++i];
    } else if (ch == '/' && !characterClass) {
      result.emplace_back();
    } else {
      result.back() += ch;
      if (pattern && ch == '[')
        characterClass = true;
      if (pattern && ch == ']')
        characterClass = false;
    }
  }
  return result;
}

std::vector<std::string> nameKeys(StringRef spelling) {
  std::vector<std::string> result(1);
  for (size_t i = 0; i < spelling.size(); ++i) {
    char ch = spelling[i];
    if (ch == '\\' && i + 1 < spelling.size()) {
      ch = spelling[++i];
      if (StringRef("/.\\[]").contains(ch))
        result.back() += '\\';
      result.back() += ch;
    } else if (ch == '/')
      result.emplace_back();
    else
      result.back() += ch;
  }
  return result;
}

// Tcl StringMatch implements the final glob match but not brace alternatives.
// Expand first, including alternative hierarchy paths, then match components.
// Preserve escapes for StringMatch and bound both expansion and parser work.
int expandGlobs(Tcl_Interp *interp, StringRef spelling,
                std::vector<std::string> &result) {
  if (spelling.size() > 65536)
    return error(interp, "find_objects pattern exceeds 64 KiB");
  std::vector<std::string> pending{spelling.str()};
  size_t work = 0, bytes = spelling.size();
  while (!pending.empty()) {
    std::string current = std::move(pending.back());
    pending.pop_back();
    if (++work > 65536)
      return error(interp, "find_objects brace expansion exceeds work limit");
    size_t open = StringRef::npos;
    for (size_t i = 0; i < current.size(); ++i) {
      if (current[i] == '\\' && i + 1 < current.size())
        ++i;
      else if (current[i] == '{') {
        open = i;
        break;
      } else if (current[i] == '}')
        return error(interp, "unmatched close brace in find_objects pattern");
    }
    if (open == StringRef::npos) {
      result.push_back(std::move(current));
      continue;
    }
    size_t arm = open + 1, close = StringRef::npos;
    unsigned depth = 1;
    std::vector<StringRef> alternatives;
    for (size_t i = arm; i < current.size(); ++i) {
      char ch = current[i];
      if (ch == '\\' && i + 1 < current.size()) {
        ++i;
        continue;
      }
      if (ch == '{' && ++depth > 256)
        return error(interp, "find_objects braces exceed 256 levels");
      if (ch == '}' && --depth == 0) {
        alternatives.push_back(StringRef(current).slice(arm, i));
        close = i;
        break;
      }
      if (ch == ',' && depth == 1) {
        alternatives.push_back(StringRef(current).slice(arm, i));
        arm = i + 1;
      }
    }
    if (close == StringRef::npos)
      return error(interp, "unmatched open brace in find_objects pattern");
    if (pending.size() + result.size() + alternatives.size() > 4096)
      return error(interp,
                   "find_objects brace expansion exceeds 4096 patterns");
    for (auto alternative : llvm::reverse(alternatives)) {
      size_t size = open + alternative.size() + current.size() - close - 1;
      if (size > 4194304 - bytes)
        return error(interp, "find_objects brace expansion exceeds 4 MiB");
      bytes += size;
      pending.push_back((StringRef(current).take_front(open) + alternative +
                         StringRef(current).drop_front(close + 1))
                            .str());
    }
  }
  return TCL_OK;
}

bool literalBrackets(StringRef pattern, bool exact) {
  bool open = false;
  for (size_t i = 0; i < pattern.size(); ++i) {
    char ch = pattern[i];
    if (ch == '\\' && i + 1 < pattern.size())
      ch = pattern[++i];
    else if (!exact)
      continue;
    if (ch == '[')
      open = true;
    if (ch == ']' && open)
      return true;
  }
  return false;
}

bool matchesExact(StringRef name, StringRef pattern, bool ignoreCase) {
  if (!ignoreCase)
    return name == pattern;
  Tcl_Size count = Tcl_NumUtfChars(name.data(), name.size());
  return count == Tcl_NumUtfChars(pattern.data(), pattern.size()) &&
         Tcl_UtfNcasecmp(name.str().c_str(), pattern.str().c_str(), count) == 0;
}

bool canSelect(StringRef pattern, StringRef name, bool exact, bool ignoreCase) {
  for (size_t i = 0; i < pattern.size(); ++i) {
    size_t open = i;
    char ch = pattern[i];
    if (ch == '\\' && i + 1 < pattern.size())
      ch = pattern[++i];
    else if (!exact)
      continue;
    if (ch != '[')
      continue;
    StringRef base = pattern.take_front(open);
    if (exact ? matchesExact(name, base, ignoreCase)
              : Tcl_StringCaseMatch(name.str().c_str(), base.str().c_str(),
                                    ignoreCase))
      return true;
  }
  return false;
}

// A conservative mandatory prefix avoids expanding unrelated large arrays.
// Alternation can bypass an anchor, and zero-count quantifiers can remove the
// preceding literal. All other regexp constructs stop prefix extraction.
std::string regexpPrefix(StringRef pattern) {
  if (!pattern.consume_front("^") || pattern.contains('|'))
    return {};
  std::string result;
  for (size_t i = 0; i < pattern.size(); ++i) {
    char ch = pattern[i];
    if (ch == '\\' && i + 1 < pattern.size()) {
      ch = pattern[++i];
      if (!StringRef("\\.[](){}*+?^$/").contains(ch))
        break;
    } else if (StringRef(".[](){}*+?^$").contains(ch)) {
      if (ch == '*' || ch == '?' || ch == '{') {
        while (!result.empty() &&
               (static_cast<unsigned char>(result.back()) & 0xc0) == 0x80)
          result.pop_back();
        if (!result.empty())
          result.pop_back();
      }
      break;
    }
    result += ch;
  }
  return result;
}

bool compatiblePrefix(StringRef a, StringRef b, bool ignoreCase) {
  if (!ignoreCase)
    return a.starts_with(b) || b.starts_with(a);
  // Tcl's regexp engine and its glob optimization need not use identical
  // Unicode case closures. Defer those cases entirely to the compiled regexp.
  auto ascii = [](StringRef value) {
    return llvm::all_of(value, [](unsigned char ch) { return ch < 128; });
  };
  if (!ascii(a) || !ascii(b))
    return true;
  Tcl_Size count = std::min(Tcl_NumUtfChars(a.data(), a.size()),
                            Tcl_NumUtfChars(b.data(), b.size()));
  return Tcl_UtfNcasecmp(a.str().c_str(), b.str().c_str(), count) == 0;
}

bool uninstantiated(Operation *op) {
  for (; op; op = op->getParentOp())
    if (auto value = op->getAttrOfType<BoolAttr>("is_uninstantiated");
        value && value.getValue())
      return true;
  return false;
}

// Enumerate declared dimensions, not flattened storage offsets (LRM 7.4).
// Each index names an element of its dimension, rather than a flattened bit
// position. Matching still uses Tcl's glob/regexp rules on selected names.
std::optional<std::pair<int64_t, int64_t>> range(Type type) {
  if (auto array = dyn_cast<slangir::PackedArrayType>(type))
    return std::pair{array.getLeft(), array.getRight()};
  if (auto array = dyn_cast<slangir::UnpackedArrayType>(type))
    return std::pair{array.getLeft(), array.getRight()};
  if (auto enumeration = dyn_cast<slangir::EnumType>(type)) {
    // Enum indexing is flat [width-1:0], even for an ascending or
    // multidimensional packed base (LRM 6.19 and 7.4.5).
    Type base = enumeration.getBaseType();
    uint64_t width = 1;
    while (auto array = dyn_cast<slangir::PackedArrayType>(base)) {
      uint64_t count =
          array.getLeft() >= array.getRight()
              ? uint64_t(array.getLeft()) - uint64_t(array.getRight())
              : uint64_t(array.getRight()) - uint64_t(array.getLeft());
      if (count >= uint64_t(std::numeric_limits<int64_t>::max()) ||
          width > uint64_t(std::numeric_limits<int64_t>::max()) / (count + 1))
        return std::nullopt;
      width *= count + 1;
      base = array.getElementType();
    }
    auto integer = dyn_cast<slangir::IntegralType>(base);
    if (!integer || !integer.getWidth() ||
        width >
            uint64_t(std::numeric_limits<int64_t>::max()) / integer.getWidth())
      return std::nullopt;
    width *= integer.getWidth();
    return std::pair{int64_t(width - 1), int64_t{0}};
  }
  if (auto integer = dyn_cast<slangir::IntegralType>(type);
      integer && integer.getWidth() > 1)
    return std::pair{integer.getLeft(), integer.getRight()};
  if (auto aggregate = dyn_cast<slangir::AggregateType>(type);
      aggregate && aggregate.getIsPacked() && aggregate.getBitWidth() >= 1 &&
      aggregate.getBitWidth() <= uint64_t(std::numeric_limits<int64_t>::max()))
    return std::pair{int64_t(aggregate.getBitWidth() - 1), int64_t{0}};
  return std::nullopt;
}
Type elementType(Type type, ArrayAttr declared, unsigned stage) {
  if (isa<slangir::EnumType>(type))
    return {};
  if (declared && stage + 1 < declared.size())
    return cast<TypeAttr>(declared[stage + 1]).getValue();
  if (auto array = dyn_cast<slangir::PackedArrayType>(type))
    return array.getElementType();
  if (auto array = dyn_cast<slangir::UnpackedArrayType>(type))
    return array.getElementType();
  return {};
}
} // namespace

DesignQuery::Path DesignQuery::Path::fromHDL(StringRef name) {
  Path result;
  for (size_t start = 0; start < name.size();) {
    bool escaped = name[start] == '\\';
    size_t end = start;
    if (escaped) {
      ++start;
      end = name.find_first_of(" \t\r\n", start);
    } else
      end = name.find('.', start);
    if (end == StringRef::npos)
      end = name.size();
    std::string component = name.slice(start, end).str();
    size_t escapedLength = escaped ? component.size() : 0;
    start = end;
    while (start < name.size() && StringRef(" \t\r\n").contains(name[start]))
      ++start;
    // Slang prints an escaped array identifier as "\\name [index]".
    // The index belongs to the same hierarchy component, but its brackets
    // are selectors rather than literal identifier characters.
    if (escaped)
      while (start < name.size() && name[start] == '[') {
        size_t close = name.find(']', start + 1);
        if (close == StringRef::npos)
          break;
        component += name.slice(start, close + 1).str();
        start = close + 1;
      }
    result.names.push_back(std::move(component));
    result.escapedLength.push_back(escapedLength);
    if (start < name.size() && name[start] == '.')
      ++start;
  }
  return result;
}

std::vector<std::string> DesignQuery::Path::keys() const {
  std::vector<std::string> result(names.size());
  for (size_t i = 0; i < names.size(); ++i) {
    for (size_t j = 0; j < names[i].size(); ++j) {
      char ch = names[i][j];
      if (ch == '/' || ch == '.' || ch == '\\' ||
          (j < escapedLength[i] && (ch == '[' || ch == ']')))
        result[i] += '\\';
      result[i] += ch;
    }
  }
  return result;
}

std::string DesignQuery::Path::upf(size_t start) const {
  std::string result;
  auto components = keys();
  for (size_t i = start; i < components.size(); ++i) {
    if (i != start)
      result += '/';
    result += components[i];
  }
  return result;
}

DesignQuery::DesignQuery(ModuleOp module) {
  std::map<std::string, std::string> models;
  module.walk([&](Operation *op) {
    auto path = op->getAttrOfType<StringAttr>("hierarchical_name");
    auto name = op->getAttrOfType<StringAttr>("name");
    if (path && name &&
        op->getName().getStringRef() == "slang.symbol.definition")
      models[path.str()] = name.str();
  });
  module.walk([&](Operation *op) {
    auto spelling = op->getAttrOfType<StringAttr>("hierarchical_name");
    if (!spelling || uninstantiated(op))
      return;
    StringRef kind = op->getName().getStringRef();
    bool scope = kind == "slang.symbol.instance" ||
                 kind == "slang.symbol.generate_block";
    bool object = scope || kind == "slang.symbol.net" ||
                  kind == "slang.symbol.variable" ||
                  kind == "slang.symbol.port";
    if (object) {
      Path path = Path::fromHDL(spelling);
      names.emplace(path.keys(), spelling.str());
      if (scope)
        scopes.emplace(spelling.str(), std::move(path));
    }
  });
  module.walk([&](Operation *op) {
    auto spelling = op->getAttrOfType<StringAttr>("hierarchical_name");
    if (!spelling || uninstantiated(op))
      return;
    auto kind =
        llvm::StringSwitch<std::optional<Kind>>(op->getName().getStringRef())
            .Case("slang.symbol.instance", Kind::Instance)
            .Case("slang.symbol.port", Kind::Port)
            .Case("slang.symbol.net", Kind::Net)
            .Case("slang.symbol.variable", Kind::Net)
            .Case("slang.symbol.statement_block", Kind::Process)
            .Default(std::nullopt);
    if (!kind)
      return;
    if (op->hasAttr("is_compiler_generated"))
      return;
    if (*kind == Kind::Process) {
      auto name = op->getAttrOfType<StringAttr>("name");
      if (!name || name.getValue().empty())
        return;
    }
    Path path = Path::fromHDL(spelling);
    auto parent = path.keys();
    if (parent.empty())
      return;
    parent.pop_back();
    auto owner = names.find(parent);
    if (!parent.empty() && (owner == names.end() || !isScope(owner->second)))
      return;
    std::string model;
    if (*kind == Kind::Instance)
      if (auto ref = op->getAttrOfType<StringAttr>("referenced_path")) {
        auto found = models.find(ref.str());
        model = found == models.end() ? ref.str() : found->second;
      }
    objects.push_back({std::move(path), op, *kind, std::move(model)});
  });
  llvm::stable_sort(objects, [](const Object &a, const Object &b) {
    return a.path.names < b.path.names;
  });
}

std::string DesignQuery::resolve(StringRef name, StringRef scope,
                                 StringRef top) const {
  if (name.empty() || name == ".")
    return scope.str();
  bool absolute = name.consume_front("/");
  auto path = Path::fromHDL(absolute ? top : scope).keys();
  size_t root = Path::fromHDL(top).names.size();
  if (!name.empty())
    for (auto &part : nameKeys(name)) {
      if (part == ".")
        continue;
      if (part == "..") {
        if (path.size() <= root)
          return {};
        path.pop_back();
      } else
        path.push_back(part);
    }
  auto found = names.find(path);
  return found == names.end() ? std::string{} : found->second;
}

std::string DesignQuery::rooted(StringRef scope, StringRef top) const {
  Path path = Path::fromHDL(scope), root = Path::fromHDL(top);
  return "/" + path.upf(root.names.size());
}
bool DesignQuery::isScope(StringRef path) const {
  return scopes.count(path.str());
}
std::string DesignQuery::parent(StringRef path) const {
  auto parts = Path::fromHDL(path).keys();
  if (parts.empty())
    return {};
  parts.pop_back();
  auto found = names.find(parts);
  return found == names.end() ? std::string{} : found->second;
}
bool DesignQuery::isTop(StringRef path) const {
  return Path::fromHDL(path).names.size() == 1;
}

int DesignQuery::find(Tcl_Interp *interp, Tcl_Size objc, Tcl_Obj *const objv[],
                      StringRef scope, StringRef top,
                      const SupplyPorts &supplyPorts) const {
  bool transitive = false, sawTransitive = false, ignoreCase = false;
  enum class Style { Glob, Regexp, Exact };
  Style style = Style::Glob;
  std::map<std::string, Tcl_Obj *> options;
  for (Tcl_Size i = 2; i < objc; ++i) {
    StringRef option = spelling(objv[i]);
    if (option == "-regexp" || option == "-exact") {
      Style next = option == "-regexp" ? Style::Regexp : Style::Exact;
      if (style == next)
        return error(interp, "duplicate UPF option " + option);
      if (style != Style::Glob)
        return error(interp,
                     "find_objects -regexp and -exact are mutually exclusive");
      style = next;
    } else if (option == "-ignore_case") {
      if (ignoreCase)
        return error(interp, "duplicate UPF option -ignore_case");
      ignoreCase = true;
    } else if (option == "-transitive") {
      if (sawTransitive)
        return error(interp, "duplicate UPF option -transitive");
      sawTransitive = transitive = true;
      if (i + 1 < objc && !spelling(objv[i + 1]).starts_with('-')) {
        int flag;
        if (Tcl_GetBooleanFromObj(interp, objv[++i], &flag) != TCL_OK)
          return TCL_ERROR;
        transitive = flag;
      }
    } else {
      if (option != "-pattern" && option != "-object_type" &&
          option != "-direction")
        return error(interp, "unsupported find_objects option: " + option);
      if (++i == objc)
        return error(interp, "missing value for " + option);
      if (!options.emplace(option.str(), objv[i]).second)
        return error(interp, "duplicate UPF option " + option);
    }
  }
  StringRef requestedScope = spelling(objv[1]);
  if (requestedScope.starts_with('/') || requestedScope.starts_with(".."))
    return error(interp,
                 "find_objects scope must be relative to current scope");
  std::string base = resolve(requestedScope, scope, top);
  auto basePath = Path::fromHDL(base).keys();
  auto currentPath = Path::fromHDL(scope).keys();
  if (!isScope(base) || !prefix(basePath, currentPath))
    return error(interp, "find_objects scope not found");
  if (!options.count("-pattern"))
    return error(interp, "find_objects requires -pattern");
  StringRef pattern = spelling(options.at("-pattern"));
  // Tcl's modified UTF-8 also represents U+0000 as C0 80.
  if (pattern.size() > 65536 || pattern.contains('\0') ||
      pattern.contains(StringRef("\xC0\x80", 2)))
    return error(
        interp,
        "find_objects pattern must have at most 64 KiB and no NUL characters");
  StringRef kind = options.count("-object_type")
                       ? spelling(options.at("-object_type"))
                       : StringRef{};
  if (options.count("-object_type") && kind != "inst" && kind != "model" &&
      kind != "port" && kind != "net" && kind != "process" &&
      kind != "supply_port")
    return error(interp, "unsupported find_objects object type: " + kind);
  std::optional<int64_t> direction;
  if (options.count("-direction")) {
    if (kind != "port" && kind != "supply_port")
      return error(interp,
                   "find_objects -direction requires port or supply_port");
    StringRef value = spelling(options.at("-direction"));
    if (value != "in" && value != "out" && value != "inout")
      return error(interp, "find_objects direction must be in, out, or inout");
    direction = value == "in" ? 0 : value == "out" ? 1 : 2;
  }
  Tcl_RegExp expression = nullptr;
  std::string requiredPrefix;
  std::vector<std::vector<std::string>> patterns;
  if (style == Style::Regexp) {
    if (pattern.contains('/'))
      return error(interp, "find_objects -regexp pattern cannot contain '/'");
    expression = Tcl_GetRegExpFromObj(interp, options.at("-pattern"),
                                      TCL_REG_ADVANCED | TCL_REG_NOSUB |
                                          (ignoreCase ? TCL_REG_NOCASE : 0));
    if (!expression)
      return TCL_ERROR;
    requiredPrefix = regexpPrefix(pattern);
    patterns.push_back({pattern.str()});
  } else if (style == Style::Exact)
    patterns.push_back(splitUPF(pattern));
  else {
    std::vector<std::string> expanded;
    if (expandGlobs(interp, pattern, expanded) != TCL_OK)
      return TCL_ERROR;
    for (auto &alternative : expanded)
      patterns.push_back(splitUPF(alternative, true));
  }

  Tcl_Obj *result = Tcl_NewListObj(0, nullptr);
  Tcl_IncrRefCount(result);
  auto release = llvm::scope_exit([&] { Tcl_DecrRefCount(result); });
  std::set<std::string> returned;
  size_t budget = 1048576;
  auto match = [&](const Path &path, const std::vector<std::string> &components,
                   StringRef model, StringRef selected,
                   bool parentsOnly) -> int {
    size_t count = path.names.size() - basePath.size();
    if (count < components.size() ||
        (!transitive && count != components.size()))
      return 0;
    for (size_t i = 0; i < components.size(); ++i) {
      if (i + 1 == components.size() && parentsOnly)
        return 1;
      StringRef candidate =
          path.names[path.names.size() - components.size() + i];
      if (i + 1 == components.size())
        candidate = !model.empty() ? model : selected;
      if (expression) {
        Tcl_Obj *text = Tcl_NewStringObj(candidate.data(), candidate.size());
        Tcl_IncrRefCount(text);
        int status = Tcl_RegExpExecObj(interp, expression, text, 0, 0, 0);
        Tcl_DecrRefCount(text);
        return status;
      }
      if (style == Style::Exact) {
        if (!matchesExact(candidate, components[i], ignoreCase))
          return 0;
      } else if (!Tcl_StringCaseMatch(candidate.str().c_str(),
                                      components[i].c_str(), ignoreCase))
        return 0;
    }
    return 1;
  };
  auto append = [&](const Path &path, StringRef selectors) {
    std::string name = path.upf(currentPath.size()) + selectors.str();
    if (returned.insert(name).second)
      Tcl_ListObjAppendElement(interp, result,
                               Tcl_NewStringObj(name.data(), name.size()));
  };
  auto visit = [&](const Path &path, Operation *decl, StringRef model,
                   bool selectable) -> int {
    if (!prefix(path.keys(), basePath) || path.names.size() <= basePath.size())
      return TCL_OK;
    for (const auto &components : patterns) {
      if (!match(path, components, {}, {}, true))
        continue;
      bool bits = selectable && decl &&
                  literalBrackets(components.back(), style == Style::Exact);
      int status = match(path, components, model, path.names.back(), false);
      if (status < 0)
        return TCL_ERROR;
      if (status)
        append(path, {});
      if (!bits)
        continue;
      if (expression && !requiredPrefix.empty() &&
          !compatiblePrefix(path.names.back(), requiredPrefix, ignoreCase))
        continue;
      if (style != Style::Regexp &&
          !canSelect(components.back(), path.names.back(),
                     style == Style::Exact, ignoreCase))
        continue;
      auto attribute = decl->getAttrOfType<TypeAttr>("semantic_type");
      auto declared =
          decl->getAttrOfType<ArrayAttr>("declared_selection_types");
      if (!attribute)
        continue;
      struct Selection {
        Type type;
        std::string suffix;
        unsigned stage;
      };
      std::vector<Selection> pending{{attribute.getValue(), {}, 0}};
      while (!pending.empty()) {
        auto selection = std::move(pending.back());
        pending.pop_back();
        if (!budget--)
          return error(interp,
                       "find_objects bit expansion exceeds 1048576 elements");
        auto bounds = range(selection.type);
        if (!bounds) {
          // A scalar whose HDL identifier literally contains brackets remains
          // an object, not a fabricated scalar bit.
          if (selection.suffix.empty() && status)
            append(path, {});
          continue;
        }
        auto [left, right] = *bounds;
        uint64_t span = left >= right ? uint64_t(left) - uint64_t(right)
                                      : uint64_t(right) - uint64_t(left);
        if (span >= budget)
          return error(interp,
                       "find_objects bit expansion exceeds 1048576 elements");
        std::vector<Selection> children;
        for (int64_t index = left;; index += left <= right ? 1 : -1) {
          --budget;
          std::string suffix =
              selection.suffix + "[" + std::to_string(index) + "]";
          std::string value = path.names.back() + suffix;
          int found = match(path, components, model, value, false);
          if (found < 0)
            return TCL_ERROR;
          if (found)
            append(path, suffix);
          Type element = elementType(selection.type, declared, selection.stage);
          if (element && range(element))
            children.push_back(
                {element, std::move(suffix), selection.stage + 1});
          if (index == right)
            break;
        }
        for (auto &child : llvm::reverse(children))
          pending.push_back(std::move(child));
      }
    }
    return TCL_OK;
  };
  if (kind == "supply_port") {
    for (const auto &[spelling, port] : supplyPorts) {
      if (!isScope(parent(spelling)))
        continue; // Abstract switch ports are not logic hierarchy scopes.
      int64_t value = port.direction == SupplyPort::In    ? 0
                      : port.direction == SupplyPort::Out ? 1
                                                          : 2;
      if (direction && *direction != value)
        continue;
      if (visit(Path::fromHDL(spelling), nullptr, {}, false) != TCL_OK)
        return TCL_ERROR;
    }
  } else {
    for (const auto &object : objects) {
      if (((kind == "inst" || kind == "model") &&
           object.kind != Kind::Instance) ||
          (kind == "port" && object.kind != Kind::Port) ||
          (kind == "net" && object.kind != Kind::Net) ||
          (kind == "process" && object.kind != Kind::Process))
        continue;
      if (direction) {
        auto value =
            object.declaration->getAttrOfType<IntegerAttr>("direction");
        if (!value || value.getInt() != *direction)
          continue;
      }
      if (visit(object.path, object.declaration,
                kind == "model" ? StringRef(object.model) : StringRef{},
                object.kind == Kind::Net || object.kind == Kind::Port) !=
          TCL_OK)
        return TCL_ERROR;
    }
  }
  Tcl_SetObjResult(interp, result);
  return TCL_OK;
}
} // namespace talos
#endif
