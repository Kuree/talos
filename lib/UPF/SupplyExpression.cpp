#include "SupplyExpression.h"
#include "ExpressionOperators.h"
#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Support/Error.h"
#include <algorithm>
#include <functional>
#include <limits>
#include <map>

using namespace mlir;
using namespace llvm;
namespace talos {
namespace {
using Opcode = upf::SupplyExpressionOpcode;
enum class Kind { Boolean, State, Real, Supply, Aggregate };
struct Node {
  Kind kind;
  SupplyToken token;
  int left = -1, right = -1;
  unsigned height = 1;
  bool hasVoltage = false;
};
class Parser {
  StringRef text;
  size_t cursor = 0;
  bool invalid = false;
  llvm::function_ref<FailureOr<SupplyReference>(StringRef)> resolve;
  llvm::function_ref<void(const Twine &)> report;
  SmallVector<Node> nodes;
  SupplyExpression result;
  int error(const Twine &message) {
    if (!invalid)
      report("UPF supply expression at byte " + Twine(cursor) + ": " + message);
    invalid = true;
    return -1;
  }
  void space() {
    while (cursor < text.size() && isSpace(text[cursor]))
      ++cursor;
  }
  bool take(StringRef spelling) {
    space();
    if (!text.drop_front(cursor).starts_with(spelling))
      return false;
    cursor += spelling.size();
    return true;
  }
  int add(Node node) {
    if (nodes.size() == 4096)
      return error("expression exceeds 4096 nodes");
    if (node.left >= 0)
      node.height = nodes[node.left].height + 1;
    if (node.right >= 0)
      node.height = std::max(node.height, nodes[node.right].height + 1);
    if (node.height > 256)
      return error("expression tree exceeds 256 levels");
    nodes.push_back(std::move(node));
    return nodes.size() - 1;
  }
  int literal(Kind kind, Opcode opcode, int32_t value = 0, double real = 0) {
    return add({kind, {opcode, std::nullopt, value, real}});
  }
  static std::optional<int32_t> state(StringRef name) {
    if (name == "OFF")
      return 0;
    if (name == "FULL_ON")
      return 1;
    if (name == "PARTIAL_ON")
      return 2;
    if (name == "UNDETERMINED")
      return 3;
    return std::nullopt;
  }
  StringRef name() {
    space();
    size_t begin = cursor;
    while (cursor < text.size() && !isSpace(text[cursor]) &&
           !StringRef("(){}!,~&|^<>=").contains(text[cursor]))
      ++cursor;
    return text.slice(begin, cursor);
  }
  int number() {
    space();
    size_t begin = cursor;
    if (cursor < text.size() && (text[cursor] == '-' || text[cursor] == '+'))
      ++cursor;
    auto digits = [&]() -> bool {
      // SV unsigned_number: an initial digit, then digits/underscores.
      // Repeated or trailing underscores are legal within a component.
      if (cursor == text.size() || !isDigit(text[cursor]))
        return false;
      while (cursor < text.size()) {
        if (isDigit(text[cursor]) || text[cursor] == '_')
          ++cursor;
        else
          break;
      }
      return true;
    };
    if (!digits())
      return error("real literal requires initial decimal digits");
    if (cursor < text.size() && text[cursor] == '.') {
      ++cursor;
      if (!digits())
        return error("real fraction requires initial decimal digits");
    }
    if (cursor < text.size() && (text[cursor] == 'e' || text[cursor] == 'E')) {
      ++cursor;
      if (cursor < text.size() && (text[cursor] == '-' || text[cursor] == '+'))
        ++cursor;
      if (!digits() || invalid)
        return error("real exponent requires digits");
    }
    std::string spelling;
    for (char c : text.slice(begin, cursor))
      if (c != '_')
        spelling.push_back(c);
    APFloat value(APFloat::IEEEdouble());
    auto status =
        value.convertFromString(spelling, APFloat::rmNearestTiesToEven);
    if (!status) {
      consumeError(status.takeError());
      return error("invalid real literal");
    }
    if (!value.isFinite())
      return error("voltage literal must be finite binary64");
    return literal(Kind::Real, Opcode::Real, 0, value.convertToDouble());
  }
  int boolean(int index) {
    if (index < 0)
      return -1;
    Node node = nodes[index];
    if (node.kind == Kind::Boolean)
      return index;
    if (node.kind == Kind::Real &&
        (node.token.real == 0 || node.token.real == 1))
      return literal(Kind::Boolean, Opcode::Boolean, node.token.real == 1);
    return error("Boolean operator requires a Boolean operand");
  }
  int op(Opcode code, Kind type, int left, int right = -1) {
    if (left < 0 ||
        (right < 0 && code != Opcode::Not && code != Opcode::BitNot))
      return -1;
    return add({type, {code, std::nullopt}, left, right});
  }
  int compare(Opcode code, int left, int right) {
    if (left < 0 || right < 0)
      return -1;
    Node a = nodes[left], b = nodes[right];
    bool equality = code == Opcode::Equal || code == Opcode::NotEqual;
    if (b.kind == Kind::Supply &&
        (a.kind == Kind::State || a.kind == Kind::Aggregate)) {
      std::swap(left, right);
      std::swap(a, b);
    }
    if (a.kind == Kind::Supply) {
      if (!equality ||
          (b.kind != Kind::Aggregate &&
           !(b.kind == Kind::State && b.token.opcode == Opcode::StateValue)))
        return error("whole supplies require equality with a state or "
                     "state/voltage aggregate");
      int ref = add({Kind::State, {Opcode::State, a.token.reference}});
      int value = literal(Kind::State, Opcode::StateValue, b.token.value);
      int result = op(Opcode::Equal, Kind::Boolean, ref, value);
      if (b.kind == Kind::Aggregate && b.hasVoltage) {
        ref = add({Kind::Real, {Opcode::Voltage, a.token.reference}});
        value = literal(Kind::Real, Opcode::Real, 0, b.token.real);
        result = op(Opcode::And, Kind::Boolean, result,
                    op(Opcode::Equal, Kind::Boolean, ref, value));
      }
      // 6.5.4: negate the entire expanded equality for !=, not each field.
      return code == Opcode::NotEqual ? op(Opcode::Not, Kind::Boolean, result)
                                      : result;
    }
    if (a.kind == Kind::Boolean && b.kind == Kind::Real)
      right = boolean(right);
    if (b.kind == Kind::Boolean && a.kind == Kind::Real)
      left = boolean(left);
    if (left < 0 || right < 0)
      return -1;
    a = nodes[left];
    b = nodes[right];
    if (a.kind != b.kind || (a.kind != Kind::Real && a.kind != Kind::State &&
                             a.kind != Kind::Boolean))
      return error("comparison operands have incompatible supply types");
    // Untyped decimal spellings have voltage semantics in a voltage
    // comparison. Do not reinterpret integer-only SV comparisons as f64
    // (large distinct integers can round to the same binary64 value).
    if (a.kind == Kind::Real && a.token.opcode == Opcode::Real &&
        b.token.opcode == Opcode::Real)
      return error("numeric comparisons require a voltage operand");
    if (a.kind != Kind::Real && !equality)
      return error("ordered comparisons require real voltage operands");
    return op(code, Kind::Boolean, left, right);
  }
  int primary(unsigned depth) {
    if (depth > 256)
      return error("expression nesting exceeds 256 levels");
    space();
    if (cursor == text.size())
      return error("expected a supply operand");
    if (take("!"))
      return op(Opcode::Not, Kind::Boolean, boolean(primary(depth + 1)));
    if (take("~")) {
      int operand = primary(depth + 1);
      if (operand < 0)
        return -1;
      if (nodes[operand].kind != Kind::Boolean)
        return error("bitwise negation requires a Boolean predicate or "
                     "explicit one-bit literal");
      return op(Opcode::BitNot, Kind::Boolean, operand);
    }
    if (take("(")) {
      int result = expression(1, depth + 1);
      if (!take(")"))
        return error("expected ')'");
      return result;
    }
    if (take("'{") || take("{")) {
      auto value = state(name());
      if (!value)
        return error("aggregate requires OFF/FULL_ON/PARTIAL_ON/UNDETERMINED");
      Node node{Kind::Aggregate, {Opcode::StateValue, std::nullopt, *value}};
      space();
      if (take("}"))
        return add(std::move(node));
      take(",");
      int voltage = number();
      if (voltage < 0)
        return -1;
      node.token.real = nodes[voltage].token.real;
      node.hasVoltage = true;
      if (!take("}"))
        return error(
            "aggregate requires one state and optional nominal voltage");
      return add(std::move(node));
    }
    for (StringRef spelling : {"1'b0", "1'b1", "1'B0", "1'B1", "'0", "'1"})
      if (take(spelling))
        return literal(Kind::Boolean, Opcode::Boolean, spelling.back() == '1');
    char c = text[cursor];
    if (isDigit(c) || c == '-' || c == '+' ||
        (c == '.' && cursor + 1 < text.size() && isDigit(text[cursor + 1])))
      return number();
    StringRef reference = name();
    if (reference.empty())
      return error("unsupported supply-expression syntax");
    if (auto value = state(reference))
      return literal(Kind::State, Opcode::StateValue, *value);
    Kind kind = Kind::Supply;
    Opcode code = Opcode::State;
    if (reference.ends_with(".state")) {
      reference = reference.drop_back(6);
      kind = Kind::State;
    } else if (reference.ends_with(".voltage")) {
      reference = reference.drop_back(8);
      kind = Kind::Real;
      code = Opcode::Voltage;
    }
    auto resolved = resolve(reference);
    if (failed(resolved)) {
      invalid = true;
      return -1;
    }
    result.required.insert(resolved->required.begin(),
                           resolved->required.end());
    return add({kind, {code, *resolved}});
  }
  int expression(unsigned minimum, unsigned depth) {
    int left = primary(depth);
    if (left < 0)
      return -1;
    while (true) {
      space();
      const ExpressionOperator<Opcode> *next = nullptr;
      for (auto &candidate : expressionOperators<Opcode>)
        if (text.drop_front(cursor).starts_with(candidate.spelling)) {
          next = &candidate;
          break;
        }
      if (!next || next->precedence < minimum)
        return left;
      cursor += next->spelling.size();
      int right = expression(next->precedence + 1, depth + 1);
      if (right < 0)
        return -1;
      if (next->precedence >= 6)
        left = compare(next->opcode, left, right);
      else {
        if (next->precedence >= 3 && (nodes[left].kind != Kind::Boolean ||
                                      nodes[right].kind != Kind::Boolean))
          return error("bitwise operators require Boolean predicates or "
                       "explicit one-bit literals");
        left = op(next->opcode, Kind::Boolean, boolean(left), boolean(right));
      }
      if (left < 0)
        return -1;
    }
  }
  void emit(int index) {
    const Node &node = nodes[index];
    if (node.left >= 0)
      emit(node.left);
    if (node.right >= 0)
      emit(node.right);
    result.tokens.push_back(node.token);
  }

public:
  Parser(StringRef text, decltype(resolve) resolve, decltype(report) report)
      : text(text), resolve(resolve), report(report) {}
  FailureOr<SupplyExpression> parse() {
    if (text.size() > 65536)
      return error("expression exceeds 64 KiB"), failure();
    int root = boolean(expression(1, 0));
    space();
    if (root < 0 || invalid)
      return failure();
    if (cursor != text.size())
      return error("unexpected trailing syntax"), failure();
    emit(root);
    return std::move(result);
  }
};
unsigned arity(Opcode opcode) {
  if (opcode <= Opcode::Boolean)
    return 0;
  return opcode == Opcode::Not || opcode == Opcode::BitNot ? 1 : 2;
}
} // namespace
FailureOr<SupplyExpression> parseSupplyExpression(
    StringRef text,
    llvm::function_ref<FailureOr<SupplyReference>(StringRef)> resolve,
    llvm::function_ref<void(const Twine &)> report) {
  return Parser(text, resolve, report).parse();
}
bool refinesSupplyExpression(
    const SupplyExpression &previous, const SupplyExpression &next,
    llvm::function_ref<bool(const SupplyObject &, const SupplyObject &)> same) {
  // 5.10/6.5.4: prove supported refinements, never blindly replace an old
  // predicate. AND can add constraints; OR must preserve implication in every
  // branch. Under negation require exact equality (avoids broadening !=).
  auto children = [](const SupplyExpression &expression) {
    SmallVector<std::pair<int, int>> result;
    SmallVector<int> stack;
    for (auto &token : expression.tokens) {
      int right = -1, left = -1;
      if (arity(token.opcode) == 2)
        right = stack.pop_back_val();
      if (arity(token.opcode))
        left = stack.pop_back_val();
      result.emplace_back(left, right);
      stack.push_back(result.size() - 1);
    }
    return result;
  };
  auto a = children(previous), b = children(next);
  unsigned budget = 65536;
  std::map<std::pair<int, int>, bool> equalMemo, refineMemo;
  std::function<bool(int, int)> equal = [&](int x, int y) {
    auto key = std::make_pair(x, y);
    if (auto it = equalMemo.find(key); it != equalMemo.end())
      return it->second;
    if (!budget)
      return false;
    --budget;
    const auto &p = previous.tokens[x], &q = next.tokens[y];
    bool result = p.opcode == q.opcode && p.value == q.value &&
                  p.real == q.real && bool(p.reference) == bool(q.reference);
    if (result && p.reference)
      result = same(p.reference->object, q.reference->object);
    if (result && a[x].first >= 0)
      result = equal(a[x].first, b[y].first);
    if (result && a[x].second >= 0)
      result = equal(a[x].second, b[y].second);
    return equalMemo[key] = result;
  };
  std::function<bool(int, int)> refine = [&](int x, int y) {
    auto key = std::make_pair(x, y);
    if (auto it = refineMemo.find(key); it != refineMemo.end())
      return it->second;
    if (!budget)
      return false;
    --budget;
    if (equal(x, y))
      return true;
    auto p = previous.tokens[x].opcode, q = next.tokens[y].opcode;
    bool result = false;
    if (q == Opcode::Or || q == Opcode::BitOr)
      result = refine(x, b[y].first) && refine(x, b[y].second);
    else if (p == Opcode::And || p == Opcode::BitAnd)
      result = refine(a[x].first, y) && refine(a[x].second, y);
    else if (q == Opcode::And || q == Opcode::BitAnd)
      result = refine(x, b[y].first) || refine(x, b[y].second);
    else if (p == Opcode::Or || p == Opcode::BitOr)
      result = refine(a[x].first, y) || refine(a[x].second, y);
    return refineMemo[key] = result;
  };
  return refine(previous.tokens.size() - 1, next.tokens.size() - 1);
}
std::optional<bool> contradictsSupplyExpression(
    const SupplyExpression &expression,
    llvm::function_ref<bool(const SupplyObject &, const SupplyObject &)> same) {
  // 5.10/6.5.4: retaining an old conjunct is not enough when a new
  // constraint specifies a conflicting state/voltage. Explore bounded
  // Boolean branches, intersecting scalar literal bounds in each branch.
  struct Atom {
    int node;
    bool truth;
  };
  using Branch = SmallVector<Atom>;
  using DNF = SmallVector<Branch>;
  SmallVector<std::pair<int, int>> children;
  SmallVector<int> stack;
  for (auto &token : expression.tokens) {
    int left = -1, right = -1;
    if (arity(token.opcode) == 2)
      right = stack.pop_back_val();
    if (arity(token.opcode))
      left = stack.pop_back_val();
    children.emplace_back(left, right);
    stack.push_back(children.size() - 1);
  }
  unsigned budget = 65536;
  bool exhausted = false;
  auto spend = [&](size_t amount = 1) {
    if (amount > budget) {
      exhausted = true;
      return false;
    }
    budget -= amount;
    return true;
  };
  auto join = [&](DNF a, DNF b, bool conjunction) {
    if ((!conjunction && a.size() + b.size() > 256) ||
        (conjunction && b.size() && a.size() > 256 / b.size())) {
      exhausted = true;
      return DNF{};
    }
    if (!conjunction) {
      size_t copies = b.size();
      for (auto &branch : b)
        copies += branch.size();
      if (!spend(copies))
        return DNF{};
      a.append(b.begin(), b.end());
      return a;
    }
    DNF result;
    for (auto &x : a)
      for (auto &y : b) {
        if (!spend(1 + x.size() + y.size()))
          return DNF{};
        Branch branch = x;
        branch.append(y.begin(), y.end());
        result.push_back(std::move(branch));
      }
    return result;
  };
  auto boolean = [&](int index) {
    auto code = expression.tokens[index].opcode;
    return code == Opcode::Boolean || code >= Opcode::Not;
  };
  std::function<DNF(int, bool)> expand = [&](int index, bool truth) -> DNF {
    if (!spend())
      return {};
    auto &token = expression.tokens[index];
    auto code = token.opcode;
    int left = children[index].first, right = children[index].second;
    if (code == Opcode::Boolean)
      return bool(token.value) == truth ? DNF{Branch{}} : DNF{};
    if (code == Opcode::Not || code == Opcode::BitNot)
      return expand(left, !truth);
    if (code == Opcode::And || code == Opcode::BitAnd || code == Opcode::Or ||
        code == Opcode::BitOr) {
      bool conjunction = code == Opcode::And || code == Opcode::BitAnd;
      return join(expand(left, truth), expand(right, truth),
                  conjunction == truth);
    }
    bool equivalence = (code == Opcode::Equal || code == Opcode::NotEqual) &&
                       boolean(left) && boolean(right);
    if (code == Opcode::BitXor || equivalence) {
      bool different = truth ^ (equivalence && code == Opcode::Equal);
      return join(join(expand(left, true), expand(right, !different), true),
                  join(expand(left, false), expand(right, different), true),
                  false);
    }
    return DNF{Branch{{index, truth}}};
  };
  DNF branches = expand(expression.tokens.size() - 1, true);
  if (exhausted)
    return std::nullopt;
  SmallVector<SupplyObject> sources;
  std::map<std::pair<SupplyObject::Kind, std::string>, unsigned> sourceIDs;
  auto sourceID = [&](const SupplyObject &object) {
    auto key = std::make_pair(object.kind, object.path);
    if (auto it = sourceIDs.find(key); it != sourceIDs.end())
      return it->second;
    unsigned id = sources.size();
    for (unsigned i = 0; i < sources.size(); ++i) {
      if (!spend())
        return 0u;
      if (same(sources[i], object)) {
        id = i;
        break;
      }
    }
    if (id == sources.size())
      sources.push_back(object);
    sourceIDs.emplace(std::move(key), id);
    return id;
  };
  auto operandKey = [&](const SupplyToken &token) {
    if (token.reference)
      return "r" + std::to_string(sourceID(token.reference->object)) + ":" +
             std::to_string(unsigned(token.opcode));
    if (token.opcode == Opcode::Real)
      return "f" + std::to_string(APFloat(token.real == 0 ? 0.0 : token.real)
                                      .bitcastToAPInt()
                                      .getZExtValue());
    return "i" + std::to_string(token.value);
  };
  struct Range {
    double lower = -std::numeric_limits<double>::infinity(),
           upper = std::numeric_limits<double>::infinity();
    bool lowerOpen = false, upperOpen = false, state = false;
    std::optional<double> equal;
    std::set<double> excluded;
  };
  for (auto &branch : branches) {
    bool conflict = false;
    std::map<std::string, bool> atoms;
    std::map<std::string, Range> ranges;
    for (auto atom : branch) {
      if (!spend())
        return std::nullopt;
      auto code = expression.tokens[atom.node].opcode;
      auto [l, r] = children[atom.node];
      const auto *left = &expression.tokens[l], *right = &expression.tokens[r];
      auto lk = operandKey(*left), rk = operandKey(*right);
      if (exhausted)
        return std::nullopt;
      if (lk == rk || (!left->reference && !right->reference)) {
        double a = lk == rk                       ? 0
                   : left->opcode == Opcode::Real ? left->real
                                                  : left->value;
        double b = lk == rk                        ? 0
                   : right->opcode == Opcode::Real ? right->real
                                                   : right->value;
        bool value = code == Opcode::Equal       ? a == b
                     : code == Opcode::NotEqual  ? a != b
                     : code == Opcode::Less      ? a < b
                     : code == Opcode::LessEqual ? a <= b
                     : code == Opcode::Greater   ? a > b
                                                 : a >= b;
        if (value != atom.truth) {
          conflict = true;
          break;
        }
        continue;
      }
      bool truth = atom.truth;
      auto canonical = code;
      if (canonical == Opcode::NotEqual) {
        canonical = Opcode::Equal;
        truth = !truth;
      }
      if (canonical == Opcode::Greater) {
        canonical = Opcode::Less;
        std::swap(lk, rk);
      } else if (canonical == Opcode::GreaterEqual) {
        canonical = Opcode::Less;
        truth = !truth;
      } else if (canonical == Opcode::LessEqual) {
        canonical = Opcode::Less;
        truth = !truth;
        std::swap(lk, rk);
      }
      if (canonical == Opcode::Equal && rk < lk)
        std::swap(lk, rk);
      auto key = std::to_string(unsigned(canonical)) + ":" + lk + ":" + rk;
      auto [found, inserted] = atoms.emplace(key, truth);
      if (!inserted && found->second != truth) {
        conflict = true;
        break;
      }
      if (!left->reference && right->reference) {
        std::swap(left, right);
        if (code == Opcode::Less)
          code = Opcode::Greater;
        else if (code == Opcode::LessEqual)
          code = Opcode::GreaterEqual;
        else if (code == Opcode::Greater)
          code = Opcode::Less;
        else if (code == Opcode::GreaterEqual)
          code = Opcode::LessEqual;
      }
      if (!left->reference || right->reference)
        continue;
      if (!atom.truth)
        switch (code) {
        case Opcode::Equal:
          code = Opcode::NotEqual;
          break;
        case Opcode::NotEqual:
          code = Opcode::Equal;
          break;
        case Opcode::Less:
          code = Opcode::GreaterEqual;
          break;
        case Opcode::LessEqual:
          code = Opcode::Greater;
          break;
        case Opcode::Greater:
          code = Opcode::LessEqual;
          break;
        case Opcode::GreaterEqual:
          code = Opcode::Less;
          break;
        default:
          llvm_unreachable("verified scalar comparison");
        }
      auto &range = ranges[operandKey(*left)];
      range.state = left->opcode == Opcode::State;
      double value = right->opcode == Opcode::Real ? right->real : right->value;
      if (code == Opcode::Equal) {
        if (range.equal && *range.equal != value) {
          conflict = true;
          break;
        }
        range.equal = value;
      } else if (code == Opcode::NotEqual)
        range.excluded.insert(value);
      else if (code == Opcode::Less || code == Opcode::LessEqual) {
        bool open = code == Opcode::Less;
        if (value < range.upper) {
          range.upper = value;
          range.upperOpen = open;
        } else if (value == range.upper)
          range.upperOpen |= open;
      } else {
        bool open = code == Opcode::Greater;
        if (value > range.lower) {
          range.lower = value;
          range.lowerOpen = open;
        } else if (value == range.lower)
          range.lowerOpen |= open;
      }
      if (range.lower > range.upper ||
          (range.lower == range.upper && (range.lowerOpen || range.upperOpen ||
                                          range.excluded.count(range.lower))))
        conflict = true;
      if (range.equal) {
        double v = *range.equal;
        conflict |= v < range.lower || v > range.upper ||
                    (v == range.lower && range.lowerOpen) ||
                    (v == range.upper && range.upperOpen) ||
                    range.excluded.count(v);
      } else if (range.state && range.excluded.count(0) &&
                 range.excluded.count(1) && range.excluded.count(2) &&
                 range.excluded.count(3))
        conflict = true;
      if (conflict)
        break;
    }
    if (!conflict)
      return false;
  }
  return true;
}
} // namespace talos
