//===- PropertyAutomaton.cpp - Deterministic automaton of an SVA property -===//
//
// IEEE 1800-2023 F.5 defines satisfaction over words. This takes the derivative
// of a property by one letter, the valuation of its Boolean atoms at a clock
// tick: a sequence through its regular-expression derivative, and a property
// through the operator's rule. Interning the results makes the states finite, and
// a recursive instance (16.12.17) is one more interned state.
//
//===----------------------------------------------------------------------===//

#include "PropertyAutomaton.h"

#include "Detail.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <map>
#include <tuple>
#include <vector>

using namespace mlir;

namespace talos::simlowering {
namespace {

using semantic::SVAssertionBinaryOperator;
using semantic::SVAssertionUnaryOperator;

constexpr unsigned kMaxAtomsPerState = 16;
constexpr unsigned kMaxStates = 256;
constexpr unsigned kMaxNodes = 1u << 18;
constexpr int64_t kMaxExpansion = 1024;

/// Letters are valuations of atoms, as one bit per atom index.
using Valuation = std::vector<bool>;

//===----------------------------------------------------------------------===//
// Sequences
//===----------------------------------------------------------------------===//

enum class RK {
  Fail,
  Empty,
  Any,
  Atom,
  NotAtom,
  Cat,
  Fuse,
  Or,
  Star,
  Inter,
  First,
  Through
};

struct Regex {
  RK kind;
  int a = -1;
  int b = -1;
  bool operator<(const Regex &o) const {
    return std::tie(kind, a, b) < std::tie(o.kind, o.a, o.b);
  }
};

//===----------------------------------------------------------------------===//
// Properties
//===----------------------------------------------------------------------===//

enum class FK {
  // The outcome of an attempt.
  PassVacuous,
  Pass,
  Fail,
  // a: sequence. b: 1 when strong.
  Sequence,
  // a: antecedent sequence still running. b: formula a match starts.
  Trigger,
  And,
  Or,
  Not,
  // a: formula after this letter. b: 1 when strong.
  Next,
  // a: formula starting at the next letter. b: 1 when that letter has to exist.
  Await,
  // a: formula holding at every letter.
  Always,
  // a: formula that some letter satisfies.
  SEventually,
  // a: left. b: right. c bit 0: strong, bit 1: until_with.
  Until,
  // a: atom. b: then. c: else.
  If,
  // a: atom. b: operand. c bit 0: accept_on, bit 1: asynchronous.
  Abort,
  // a: index of the call body.
  Call,
};

struct Formula {
  FK kind;
  int a = -1;
  int b = -1;
  int c = -1;
  std::vector<int> operands = {};
  bool operator<(const Formula &o) const {
    return std::tie(kind, a, b, c, operands) <
           std::tie(o.kind, o.a, o.b, o.c, o.operands);
  }
};

class Compiler {
public:
  Compiler(bool strongSequences,
           llvm::function_ref<bool(Operation *)> sameClock)
      : strongSequences(strongSequences), sameClock(sameClock) {
    failRegex = internRegex({RK::Fail});
    emptyRegex = internRegex({RK::Empty});
    anyRegex = internRegex({RK::Any});
    vacuous = intern({FK::PassVacuous});
    pass = intern({FK::Pass});
    fail = intern({FK::Fail});
  }

  FailureOr<PropertyAutomaton> compile(Operation *property);

private:
  bool strongSequences;
  llvm::function_ref<bool(Operation *)> sameClock;
  bool invalid = false;

  std::vector<Regex> regexes;
  std::map<Regex, int> regexIds;
  std::vector<Formula> formulas;
  std::map<Formula, int> formulaIds;
  SmallVector<Operation *> atoms;
  llvm::DenseMap<Operation *, int> atomIds;
  SmallVector<int> asyncAtoms;
  std::vector<int> callBodies;
  struct ActiveInstance {
    StringRef path;
    SmallVector<Operation *> arguments;
    int call;
  };
  std::vector<ActiveInstance> activeInstances;

  int failRegex, emptyRegex, anyRegex;
  int vacuous, pass, fail;

  LogicalResult reject(Operation *at, const Twine &message) {
    invalid = true;
    emitError(getSemanticLocation(at)) << message;
    return failure();
  }

  int internRegex(Regex regex) {
    auto [found, inserted] = regexIds.try_emplace(regex, regexes.size());
    if (inserted)
      regexes.push_back(regex);
    return found->second;
  }
  int intern(Formula formula) {
    auto [found, inserted] = formulaIds.try_emplace(formula, formulas.size());
    if (inserted)
      formulas.push_back(formula);
    return found->second;
  }
  int atomOf(Operation *expression) {
    auto [found, inserted] = atomIds.try_emplace(expression, atoms.size());
    if (inserted)
      atoms.push_back(expression);
    return found->second;
  }

  // Regular expression constructors, with the algebra that keeps them finite.
  int rAtom(int atom) { return internRegex({RK::Atom, atom}); }
  int rCat(int x, int y) {
    if (x == failRegex || y == failRegex)
      return failRegex;
    if (x == emptyRegex)
      return y;
    if (y == emptyRegex)
      return x;
    if (regexes[x].kind == RK::Cat)
      return rCat(regexes[x].a, rCat(regexes[x].b, y));
    return internRegex({RK::Cat, x, y});
  }
  // F.5.2: the operands of ##0 overlap on one letter, so neither can be empty.
  int rFuse(int x, int y) {
    if (x == failRegex || y == failRegex || x == emptyRegex || y == emptyRegex)
      return failRegex;
    return internRegex({RK::Fuse, x, y});
  }
  int rOr(int x, int y) {
    if (x == failRegex || x == y)
      return y;
    if (y == failRegex)
      return x;
    // Keep alternatives right-nested, sorted and unique.
    SmallVector<int> alternatives;
    auto flatten = [&](auto &&self, int regex) -> void {
      if (regexes[regex].kind == RK::Or) {
        self(self, regexes[regex].a);
        self(self, regexes[regex].b);
      } else {
        alternatives.push_back(regex);
      }
    };
    flatten(flatten, x);
    flatten(flatten, y);
    llvm::sort(alternatives);
    alternatives.erase(llvm::unique(alternatives), alternatives.end());
    int result = alternatives.back();
    for (size_t index = alternatives.size() - 1; index-- > 0;)
      result = internRegex({RK::Or, alternatives[index], result});
    return result;
  }
  int rStar(int x) {
    if (x == failRegex || x == emptyRegex)
      return emptyRegex;
    if (regexes[x].kind == RK::Star)
      return x;
    return internRegex({RK::Star, x});
  }
  int rInter(int x, int y) {
    if (x == failRegex || y == failRegex)
      return failRegex;
    if (x == y)
      return x;
    if (x > y)
      std::swap(x, y);
    return internRegex({RK::Inter, x, y});
  }
  int rFirst(int x) {
    if (x == failRegex || x == emptyRegex)
      return x;
    return internRegex({RK::First, x});
  }
  int rThrough(int atom, int x) {
    if (x == failRegex || x == emptyRegex)
      return x;
    return internRegex({RK::Through, atom, x});
  }
  /// x repeated between `minimum` and `maximum` times, or without a maximum.
  int rRepeat(int x, int64_t minimum, std::optional<int64_t> maximum) {
    int result = emptyRegex;
    int optional = emptyRegex;
    if (maximum) {
      for (int64_t index = *maximum; index > minimum; --index)
        optional = rOr(emptyRegex, rCat(x, optional));
      result = optional;
    } else {
      result = rStar(x);
    }
    for (int64_t index = 0; index != minimum; ++index)
      result = rCat(x, result);
    return result;
  }

  bool nullable(int regex) const {
    const Regex &r = regexes[regex];
    switch (r.kind) {
    case RK::Fail:
    case RK::Any:
    case RK::Atom:
    case RK::NotAtom:
    case RK::Fuse:
      return false;
    case RK::Empty:
    case RK::Star:
      return true;
    case RK::Cat:
    case RK::Inter:
      return nullable(r.a) && nullable(r.b);
    case RK::Or:
      return nullable(r.a) || nullable(r.b);
    case RK::First:
      return nullable(r.a);
    case RK::Through:
      return nullable(r.b);
    }
    return false;
  }

  int derive(int regex, const Valuation &letter) {
    Regex r = regexes[regex];
    switch (r.kind) {
    case RK::Fail:
    case RK::Empty:
      return failRegex;
    case RK::Any:
      return emptyRegex;
    case RK::Atom:
      return letter[r.a] ? emptyRegex : failRegex;
    case RK::NotAtom:
      return letter[r.a] ? failRegex : emptyRegex;
    case RK::Or:
      return rOr(derive(r.a, letter), derive(r.b, letter));
    case RK::Cat: {
      int left = rCat(derive(r.a, letter), r.b);
      return nullable(r.a) ? rOr(left, derive(r.b, letter)) : left;
    }
    case RK::Fuse: {
      // A match of the left that ends on this letter shares it with the right.
      int derived = derive(r.a, letter);
      int left = rFuse(derived, r.b);
      return nullable(derived) ? rOr(left, derive(r.b, letter)) : left;
    }
    case RK::Star:
      return rCat(derive(r.a, letter), regex);
    case RK::Inter:
      return rInter(derive(r.a, letter), derive(r.b, letter));
    case RK::First: {
      // F.5.2: first_match ends with its first match.
      int derived = derive(r.a, letter);
      return nullable(derived) ? emptyRegex : rFirst(derived);
    }
    case RK::Through:
      return letter[r.a] ? rThrough(r.a, derive(r.b, letter)) : failRegex;
    }
    return failRegex;
  }

  // Property constructors. A Pass among And's operands records that a nonvacuous
  // result has been seen (16.14.8).
  int fAnd(ArrayRef<int> parts) {
    std::vector<int> operands;
    bool nonvacuous = false;
    bool allVacuous = true;
    for (int part : parts) {
      if (part == fail)
        return fail;
      if (part == vacuous)
        continue;
      if (part == pass) {
        nonvacuous = true;
        continue;
      }
      allVacuous = false;
      if (formulas[part].kind == FK::And) {
        for (int nested : formulas[part].operands) {
          if (nested == pass)
            nonvacuous = true;
          else
            operands.push_back(nested);
        }
      } else {
        operands.push_back(part);
      }
    }
    if (allVacuous)
      return nonvacuous ? pass : vacuous;
    if (nonvacuous)
      operands.push_back(pass);
    llvm::sort(operands);
    operands.erase(std::unique(operands.begin(), operands.end()),
                   operands.end());
    if (operands.size() == 1)
      return operands.front();
    Formula formula{FK::And};
    formula.operands = std::move(operands);
    return intern(std::move(formula));
  }
  int fOr(ArrayRef<int> parts) {
    std::vector<int> operands;
    bool sawVacuous = false;
    for (int part : parts) {
      if (part == pass)
        return pass;
      if (part == fail)
        continue;
      if (part == vacuous) {
        sawVacuous = true;
        continue;
      }
      if (formulas[part].kind == FK::Or)
        llvm::append_range(operands, formulas[part].operands);
      else
        operands.push_back(part);
    }
    // F.5.3: the disjunction already holds. It is vacuous here, as any other
    // disjunct that could still make it nonvacuous only changes the action class.
    if (sawVacuous)
      return vacuous;
    if (operands.empty())
      return fail;
    llvm::sort(operands);
    operands.erase(std::unique(operands.begin(), operands.end()),
                   operands.end());
    if (operands.size() == 1)
      return operands.front();
    Formula formula{FK::Or};
    formula.operands = std::move(operands);
    return intern(std::move(formula));
  }
  int fNot(int part) {
    if (part == fail)
      return pass;
    if (part == pass || part == vacuous)
      return fail;
    if (formulas[part].kind == FK::Not)
      return formulas[part].a;
    return intern({FK::Not, part});
  }
  int fNext(int part, bool strong) {
    return intern({FK::Next, part, strong ? 1 : 0});
  }
  int fSequence(int regex, bool strong) {
    return intern({FK::Sequence, regex, strong ? 1 : 0});
  }
  int fTrigger(int regex, int consequent) {
    // Without a letter left to match, no more obligations can start.
    if (regex == failRegex || regex == emptyRegex)
      return vacuous;
    return intern({FK::Trigger, regex, consequent});
  }

  /// The formula after `letter`.
  int step(int formula, const Valuation &letter) {
    Formula f = formulas[formula];
    switch (f.kind) {
    case FK::PassVacuous:
    case FK::Pass:
    case FK::Fail:
      return formula;
    case FK::Sequence: {
      int derived = derive(f.a, letter);
      if (nullable(derived))
        return pass;
      return derived == failRegex ? fail : fSequence(derived, f.b != 0);
    }
    case FK::Trigger: {
      // F.5.3: the consequent starts on the letter that ends each match.
      int derived = derive(f.a, letter);
      int pending = fTrigger(derived, f.b);
      return nullable(derived) ? fAnd({step(f.b, letter), pending}) : pending;
    }
    case FK::And: {
      SmallVector<int> parts;
      for (int operand : f.operands)
        parts.push_back(step(operand, letter));
      return fAnd(parts);
    }
    case FK::Or: {
      SmallVector<int> parts;
      for (int operand : f.operands)
        parts.push_back(step(operand, letter));
      return fOr(parts);
    }
    case FK::Not:
      return fNot(step(f.a, letter));
    case FK::Next:
      return intern({FK::Await, f.a, f.b});
    case FK::Await:
      return step(f.a, letter);
    case FK::Always:
      return fAnd({step(f.a, letter), formula});
    case FK::SEventually:
      return fOr({step(f.a, letter), formula});
    case FK::Until: {
      int left = step(f.a, letter);
      int right = step(f.b, letter);
      if (f.c & 2)
        return fOr({fAnd({left, right}), fAnd({left, formula})});
      return fOr({right, fAnd({left, formula})});
    }
    case FK::If:
      return step(letter[f.a] ? f.b : f.c, letter);
    case FK::Abort: {
      // 16.12.14: the abort condition decides the property as soon as it holds.
      if (letter[f.a])
        return (f.c & 1) != 0 ? vacuous : fail;
      int inner = step(f.b, letter);
      if (inner == pass || inner == vacuous || inner == fail)
        return inner;
      return intern({FK::Abort, f.a, inner, f.c});
    }
    case FK::Call:
      return step(callBodies[f.a], letter);
    }
    return fail;
  }

  /// `formula` once the asynchronous abort condition `atom` is true between
  /// ticks. It reaches the aborts that have started; a Trigger's consequent and
  /// the operand of Next or Call have not.
  int fire(int formula, int atom) {
    Formula f = formulas[formula];
    switch (f.kind) {
    case FK::And: {
      SmallVector<int> parts;
      for (int operand : f.operands)
        parts.push_back(fire(operand, atom));
      return fAnd(parts);
    }
    case FK::Or: {
      SmallVector<int> parts;
      for (int operand : f.operands)
        parts.push_back(fire(operand, atom));
      return fOr(parts);
    }
    case FK::Not:
      return fNot(fire(f.a, atom));
    case FK::Abort: {
      if (f.a == atom && (f.c & 2) != 0)
        return (f.c & 1) != 0 ? vacuous : fail;
      int inner = fire(f.b, atom);
      if (inner == pass || inner == vacuous || inner == fail)
        return inner;
      return intern({FK::Abort, f.a, inner, f.c});
    }
    default:
      return formula;
    }
  }

  /// F.5.3: an attempt still pending when the word ends holds unless a strong
  /// operator still needs a letter.
  bool passesAtEnd(int formula, llvm::DenseSet<int> &calls) {
    const Formula &f = formulas[formula];
    switch (f.kind) {
    case FK::PassVacuous:
    case FK::Pass:
      return true;
    case FK::Fail:
      return false;
    case FK::Sequence:
    case FK::Next:
    case FK::Await:
      return f.b == 0;
    case FK::Trigger:
    case FK::Always:
      return true;
    case FK::SEventually:
      return false;
    case FK::And:
      return llvm::all_of(f.operands, [&](int operand) {
        return passesAtEnd(operand, calls);
      });
    case FK::Or:
      return llvm::any_of(f.operands, [&](int operand) {
        return passesAtEnd(operand, calls);
      });
    case FK::Not:
      return !passesAtEnd(f.a, calls);
    case FK::Until:
      return (f.c & 1) == 0;
    case FK::If:
      return passesAtEnd(f.b, calls) && passesAtEnd(f.c, calls);
    case FK::Abort:
      return passesAtEnd(f.b, calls);
    case FK::Call:
      return !calls.insert(f.a).second || passesAtEnd(callBodies[f.a], calls);
    }
    return true;
  }

  void collectRegexAtoms(int regex, llvm::DenseSet<int> &seen,
                         SmallVectorImpl<int> &result) {
    const Regex &r = regexes[regex];
    switch (r.kind) {
    case RK::Fail:
    case RK::Empty:
    case RK::Any:
      return;
    case RK::Atom:
    case RK::NotAtom:
      if (seen.insert(r.a).second)
        result.push_back(r.a);
      return;
    case RK::Through:
      if (seen.insert(r.a).second)
        result.push_back(r.a);
      collectRegexAtoms(r.b, seen, result);
      return;
    case RK::Star:
    case RK::First:
      collectRegexAtoms(r.a, seen, result);
      return;
    case RK::Cat:
    case RK::Fuse:
    case RK::Or:
    case RK::Inter:
      collectRegexAtoms(r.a, seen, result);
      collectRegexAtoms(r.b, seen, result);
      return;
    }
  }
  /// The atoms the next letter of `formula` can depend on.
  void collectAtoms(int formula, llvm::DenseSet<int> &seen,
                    llvm::DenseSet<int> &visited, SmallVectorImpl<int> &result) {
    if (!visited.insert(formula).second)
      return;
    const Formula &f = formulas[formula];
    switch (f.kind) {
    case FK::PassVacuous:
    case FK::Pass:
    case FK::Fail:
    case FK::Next:
      return;
    case FK::Sequence:
      collectRegexAtoms(f.a, seen, result);
      return;
    case FK::Trigger:
      collectRegexAtoms(f.a, seen, result);
      collectAtoms(f.b, seen, visited, result);
      return;
    case FK::And:
    case FK::Or:
      for (int operand : f.operands)
        collectAtoms(operand, seen, visited, result);
      return;
    case FK::Not:
    case FK::Await:
    case FK::Always:
    case FK::SEventually:
      collectAtoms(f.a, seen, visited, result);
      return;
    case FK::Until:
      collectAtoms(f.a, seen, visited, result);
      collectAtoms(f.b, seen, visited, result);
      return;
    case FK::If:
      if (seen.insert(f.a).second)
        result.push_back(f.a);
      collectAtoms(f.b, seen, visited, result);
      collectAtoms(f.c, seen, visited, result);
      return;
    case FK::Abort:
      if (seen.insert(f.a).second)
        result.push_back(f.a);
      collectAtoms(f.b, seen, visited, result);
      return;
    case FK::Call:
      collectAtoms(callBodies[f.a], seen, visited, result);
      return;
    }
  }

  // Building from the semantic operations.
  FailureOr<int> buildSequence(Operation *operation);
  FailureOr<int> buildProperty(Operation *operation);
  FailureOr<int> buildBooleanOperand(Operation *operation);
  bool isProperty(Operation *operation);
  FailureOr<int> applyRepetition(semantic::SVSimpleAssertionExprOp simple,
                                 int body);
  FailureOr<int> buildInstanceProperty(
      semantic::SVAssertionInstanceExpressionOp instance);
  FailureOr<int> buildTemporalUnary(semantic::SVUnaryAssertionExprOp unary);
};

/// Whether two actual arguments are the same expression, ignoring source facts.
static bool sameExpression(Operation *left, Operation *right) {
  if (left->getName() != right->getName())
    return false;
  for (StringRef name : {"referenced_path", "constant_value", "operator_kind",
                         "callee_name"})
    if (left->getAttr(name) != right->getAttr(name))
      return false;
  SmallVector<Operation *> leftChildren = getChildren(left);
  SmallVector<Operation *> rightChildren = getChildren(right);
  if (leftChildren.size() != rightChildren.size())
    return false;
  for (auto [l, r] : llvm::zip_equal(leftChildren, rightChildren))
    if (!sameExpression(l, r))
      return false;
  return true;
}

bool Compiler::isProperty(Operation *operation) {
  if (auto instance =
          dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation)) {
    if (instance.getIsRecursiveProperty() || !instance.getHasExpandedBody())
      return true;
    return isProperty(getChildren(instance).front());
  }
  if (auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(simple);
    return children.size() == 1 &&
           isa<semantic::SVAssertionInstanceExpressionOp>(children.front()) &&
           isProperty(children.front());
  }
  if (auto clocking = dyn_cast<semantic::SVClockingAssertionExprOp>(operation))
    return isProperty(getChildren(clocking).back());
  if (auto binary = dyn_cast<semantic::SVBinaryAssertionExprOp>(operation)) {
    switch (binary.getOperatorKind()) {
    case SVAssertionBinaryOperator::And:
    case SVAssertionBinaryOperator::Or: {
      SmallVector<Operation *> operands = getChildren(binary);
      return isProperty(operands.front()) || isProperty(operands.back());
    }
    case SVAssertionBinaryOperator::Intersect:
    case SVAssertionBinaryOperator::Throughout:
    case SVAssertionBinaryOperator::Within:
      return false;
    default:
      return true;
    }
  }
  return isa<semantic::SVUnaryAssertionExprOp,
             semantic::SVConditionalAssertionExprOp,
             semantic::SVStrongWeakAssertionExprOp,
             semantic::SVAbortAssertionExprOp,
             semantic::SVDisableIffAssertionExprOp>(operation);
}

FailureOr<int> Compiler::applyRepetition(semantic::SVSimpleAssertionExprOp simple,
                                         int body) {
  if (!simple.getHasRepetition())
    return body;
  int64_t minimum = simple.getRepetitionMin().value_or(0);
  std::optional<int64_t> maximum;
  if (!simple.getRepetitionIsUnbounded())
    maximum = simple.getRepetitionMax().value_or(minimum);
  if (minimum > kMaxExpansion || (maximum && *maximum > kMaxExpansion))
    return reject(simple, "property automaton repetition exceeds its limit");
  if (simple.getRepetitionKind() ==
      semantic::SVSequenceRepetitionKind::Consecutive)
    return rRepeat(body, minimum, maximum);
  // 16.9.2: goto and nonconsecutive repetition apply to one Boolean.
  SmallVector<Operation *> children = getChildren(simple);
  if (isa<semantic::SVAssertionInstanceExpressionOp>(children.front()))
    return reject(simple, "goto and nonconsecutive repetition require a Boolean");
  int gap = internRegex({RK::NotAtom, regexes[body].a});
  int occurrence = rCat(rStar(gap), body);
  int repeated = rRepeat(occurrence, minimum, maximum);
  if (simple.getRepetitionKind() == semantic::SVSequenceRepetitionKind::GoTo)
    return repeated;
  return rCat(repeated, rStar(gap));
}

FailureOr<int> Compiler::buildSequence(Operation *operation) {
  if (auto instance =
          dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation)) {
    if (instance.getLocalVariableCount() != 0)
      return reject(instance, "property automaton has no local variables");
    if (!instance.getHasExpandedBody())
      return reject(instance, "sequence instance has no expanded body");
    return buildSequence(getChildren(instance).front());
  }
  if (auto clocking = dyn_cast<semantic::SVClockingAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(clocking);
    if (!sameClock(children.front()))
      return reject(clocking,
                    "property automaton requires one clock for the property");
    return buildSequence(children.back());
  }
  if (auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(simple);
    if (children.size() != 1)
      return reject(simple, "malformed simple sequence");
    int body;
    if (isa<semantic::SVAssertionInstanceExpressionOp>(children.front())) {
      FailureOr<int> nested = buildSequence(children.front());
      if (failed(nested))
        return failure();
      body = *nested;
    } else {
      body = rAtom(atomOf(children.front()));
    }
    return applyRepetition(simple, body);
  }
  if (auto concat = dyn_cast<semantic::SVSequenceConcatExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(concat);
    ArrayAttr delays = concat.getDelays();
    if (children.empty() || delays.size() != children.size())
      return reject(concat, "malformed sequence concatenation");
    std::optional<int> result;
    for (auto [index, child] : llvm::enumerate(children)) {
      auto delay = cast<DictionaryAttr>(delays[index]);
      int64_t minimum = delay.getAs<IntegerAttr>("min").getInt();
      bool unbounded = delay.getAs<BoolAttr>("is_unbounded").getValue();
      int64_t maximum =
          unbounded ? minimum : delay.getAs<IntegerAttr>("max").getInt();
      if (minimum > kMaxExpansion || (!unbounded && maximum > kMaxExpansion))
        return reject(concat, "property automaton delay exceeds its limit");
      FailureOr<int> nested = buildSequence(child);
      if (failed(nested))
        return failure();
      // The letters a delay of `count` skips before the next element, for a
      // left operand that ends on the letter before them (F.3.4.2).
      auto joined = [&](int64_t count) {
        int gap = rRepeat(anyRegex, count, count);
        if (!result)
          return rCat(gap, *nested);
        if (count == 0)
          return rFuse(*result, *nested);
        return rCat(*result, rCat(rRepeat(anyRegex, count - 1, count - 1), *nested));
      };
      int combined = failRegex;
      if (unbounded) {
        // ##[m:$]: at least m letters on, by any number after the minimum.
        int tail = rCat(rStar(anyRegex), *nested);
        combined = !result
                       ? rCat(rRepeat(anyRegex, minimum, minimum), tail)
                       : minimum == 0
                             ? rOr(rFuse(*result, *nested), rCat(*result, tail))
                             : rCat(*result,
                                    rCat(rRepeat(anyRegex, minimum - 1, minimum - 1),
                                         tail));
      } else {
        for (int64_t count = minimum; count <= maximum; ++count)
          combined = rOr(combined, joined(count));
      }
      result = combined;
    }
    return *result;
  }
  if (auto binary = dyn_cast<semantic::SVBinaryAssertionExprOp>(operation)) {
    SmallVector<Operation *> operands = getChildren(binary);
    if (operands.size() != 2)
      return reject(binary, "malformed binary sequence");
    SVAssertionBinaryOperator kind = binary.getOperatorKind();
    if (kind == SVAssertionBinaryOperator::Throughout) {
      FailureOr<int> condition = buildBooleanOperand(operands.front());
      FailureOr<int> body = buildSequence(operands.back());
      if (failed(condition) || failed(body))
        return failure();
      return rThrough(*condition, *body);
    }
    FailureOr<int> left = buildSequence(operands.front());
    FailureOr<int> right = buildSequence(operands.back());
    if (failed(left) || failed(right))
      return failure();
    int anything = rStar(anyRegex);
    switch (kind) {
    case SVAssertionBinaryOperator::Or:
      return rOr(*left, *right);
    case SVAssertionBinaryOperator::Intersect:
      return rInter(*left, *right);
    case SVAssertionBinaryOperator::And:
      // F.3.4.2: the operands match together and end at the later end point.
      return rOr(rInter(rCat(*left, anything), *right),
                 rInter(*left, rCat(*right, anything)));
    case SVAssertionBinaryOperator::Within:
      return rInter(rCat(anything, rCat(*left, anything)), *right);
    default:
      return reject(binary, "property operator is not a sequence operator");
    }
  }
  if (auto first = dyn_cast<semantic::SVFirstMatchAssertionExprOp>(operation)) {
    if (first.getMatchItemCount() != 0)
      return reject(first, "property automaton has no sequence match items");
    FailureOr<int> nested = buildSequence(getChildren(first).front());
    if (failed(nested))
      return failure();
    return rFirst(*nested);
  }
  if (auto matched = dyn_cast<semantic::SVSequenceWithMatchExprOp>(operation)) {
    if (matched.getMatchItemCount() != 0 || matched.getHasRepetition())
      return reject(matched, "property automaton has no sequence match items");
    return buildSequence(getChildren(matched).front());
  }
  return reject(operation, "this sequence operator is not supported by the "
                           "property automaton");
}

FailureOr<int> Compiler::buildBooleanOperand(Operation *operation) {
  while (auto instance =
             dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation))
    operation = getChildren(instance).front();
  if (auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(simple);
    if (children.size() == 1 && !simple.getHasRepetition() &&
        !isa<semantic::SVAssertionInstanceExpressionOp>(children.front()))
      return atomOf(children.front());
  }
  return reject(operation, "this operand must be a Boolean expression");
}

FailureOr<int> Compiler::buildInstanceProperty(
    semantic::SVAssertionInstanceExpressionOp instance) {
  if (instance.getLocalVariableCount() != 0)
    return reject(instance, "property automaton has no local variables");
  StringRef path = instance.getReferencedPath();
  SmallVector<Operation *> children = getChildren(instance);
  ArrayRef<Operation *> arguments =
      children.empty() ? ArrayRef<Operation *>{}
                       : ArrayRef<Operation *>(children).drop_front();
  // 16.12.17: a recursive instance is the state its enclosing instance is in.
  for (const ActiveInstance &active : activeInstances) {
    if (active.path != path)
      continue;
    bool expanded = instance.getHasExpandedBody();
    size_t count = static_cast<size_t>(instance.getArgumentCount());
    if (expanded && (count != active.arguments.size() ||
                     !llvm::all_of_zip(arguments.take_front(count),
                                       active.arguments, sameExpression)))
      return reject(instance, "a recursive property instance that changes its "
                              "arguments has no finite automaton");
    return intern({FK::Call, active.call});
  }
  if (!instance.getHasExpandedBody() || children.empty())
    return reject(instance, "property instance has no expanded body");
  int call = callBodies.size();
  callBodies.push_back(fail);
  activeInstances.push_back(
      {path,
       SmallVector<Operation *>(
           arguments.take_front(static_cast<size_t>(instance.getArgumentCount()))),
       call});
  FailureOr<int> body = buildProperty(children.front());
  activeInstances.pop_back();
  if (failed(body))
    return failure();
  callBodies[call] = *body;
  return intern({FK::Call, call});
}

FailureOr<int>
Compiler::buildTemporalUnary(semantic::SVUnaryAssertionExprOp unary) {
  FailureOr<int> operand = buildProperty(getChildren(unary).front());
  if (failed(operand))
    return failure();
  SVAssertionUnaryOperator kind = unary.getOperatorKind();
  bool hasRange = unary.getHasRange();
  int64_t minimum = hasRange ? unary.getRangeMin().value_or(0) : 0;
  bool unbounded = !hasRange || unary.getRangeIsUnbounded();
  int64_t maximum = unbounded ? minimum : unary.getRangeMax().value_or(minimum);
  if (minimum > kMaxExpansion || maximum > kMaxExpansion)
    return reject(unary, "property automaton range exceeds its limit");
  auto delayed = [&](int formula, int64_t count, bool strong) {
    for (int64_t index = 0; index != count; ++index)
      formula = fNext(formula, strong);
    return formula;
  };
  switch (kind) {
  case SVAssertionUnaryOperator::Not:
    return fNot(*operand);
  case SVAssertionUnaryOperator::NextTime:
  case SVAssertionUnaryOperator::SNextTime:
    // nexttime [n]: the operand at the nth tick; no range means one.
    return delayed(*operand, hasRange ? minimum : 1,
                   kind == SVAssertionUnaryOperator::SNextTime);
  case SVAssertionUnaryOperator::Always:
  case SVAssertionUnaryOperator::SAlways: {
    bool strong = kind == SVAssertionUnaryOperator::SAlways;
    if (unbounded)
      return delayed(intern({FK::Always, *operand}), minimum, strong);
    int formula = *operand;
    for (int64_t index = minimum; index != maximum; ++index)
      formula = fAnd({*operand, fNext(formula, strong)});
    return delayed(formula, minimum, strong);
  }
  case SVAssertionUnaryOperator::Eventually:
  case SVAssertionUnaryOperator::SEventually: {
    bool strong = kind == SVAssertionUnaryOperator::SEventually;
    if (unbounded)
      return delayed(intern({FK::SEventually, *operand}), minimum, strong);
    int formula = *operand;
    for (int64_t index = minimum; index != maximum; ++index)
      formula = fOr({*operand, fNext(formula, strong)});
    return delayed(formula, minimum, strong);
  }
  }
  return reject(unary, "unknown property operator");
}

FailureOr<int> Compiler::buildProperty(Operation *operation) {
  if (!isProperty(operation)) {
    FailureOr<int> sequence = buildSequence(operation);
    if (failed(sequence))
      return failure();
    return fSequence(*sequence, strongSequences);
  }
  if (auto instance =
          dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation))
    return buildInstanceProperty(instance);
  if (auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(operation))
    return buildProperty(getChildren(simple).front());
  if (auto clocking = dyn_cast<semantic::SVClockingAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(clocking);
    if (!sameClock(children.front()))
      return reject(clocking,
                    "property automaton requires one clock for the property");
    return buildProperty(children.back());
  }
  // The assertion's own monitor applies the outermost disable iff, the only one
  // a property can have (16.12).
  if (auto disabled = dyn_cast<semantic::SVDisableIffAssertionExprOp>(operation))
    return buildProperty(getChildren(disabled).back());
  if (auto strong = dyn_cast<semantic::SVStrongWeakAssertionExprOp>(operation)) {
    FailureOr<int> sequence = buildSequence(getChildren(strong).front());
    if (failed(sequence))
      return failure();
    return fSequence(*sequence, strong.getStrength() ==
                                    semantic::SVAssertionStrength::Strong);
  }
  if (auto unary = dyn_cast<semantic::SVUnaryAssertionExprOp>(operation))
    return buildTemporalUnary(unary);
  if (auto conditional =
          dyn_cast<semantic::SVConditionalAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(conditional);
    FailureOr<int> condition = atomOf(children.front());
    FailureOr<int> whenTrue = buildProperty(children[1]);
    FailureOr<int> whenFalse =
        conditional.getHasElse() ? buildProperty(children[2])
                                 : FailureOr<int>(vacuous);
    if (failed(whenTrue) || failed(whenFalse))
      return failure();
    return intern({FK::If, *condition, *whenTrue, *whenFalse});
  }
  if (auto abort = dyn_cast<semantic::SVAbortAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(abort);
    FailureOr<int> operand = buildProperty(children.back());
    if (failed(operand))
      return failure();
    int atom = atomOf(children.front());
    if (!abort.getIsSynchronous() && !llvm::is_contained(asyncAtoms, atom))
      asyncAtoms.push_back(atom);
    return intern(
        {FK::Abort, atom, *operand,
         (abort.getAction() == semantic::SVAssertionAbortAction::Accept ? 1 : 0) |
             (abort.getIsSynchronous() ? 0 : 2)});
  }
  if (auto binary = dyn_cast<semantic::SVBinaryAssertionExprOp>(operation)) {
    SmallVector<Operation *> operands = getChildren(binary);
    if (operands.size() != 2)
      return reject(binary, "malformed binary property");
    SVAssertionBinaryOperator kind = binary.getOperatorKind();
    switch (kind) {
    case SVAssertionBinaryOperator::OverlappedImplication:
    case SVAssertionBinaryOperator::NonOverlappedImplication:
    case SVAssertionBinaryOperator::OverlappedFollowedBy:
    case SVAssertionBinaryOperator::NonOverlappedFollowedBy: {
      FailureOr<int> antecedent = buildSequence(operands.front());
      FailureOr<int> consequent = buildProperty(operands.back());
      if (failed(antecedent) || failed(consequent))
        return failure();
      // F.3.4.3.5: R |=> P is (R ##1 1) |-> P, and the followed-by operators are
      // the duals of the implications.
      bool nonoverlapped =
          kind == SVAssertionBinaryOperator::NonOverlappedImplication ||
          kind == SVAssertionBinaryOperator::NonOverlappedFollowedBy;
      int regex = nonoverlapped ? rCat(*antecedent, anyRegex) : *antecedent;
      if (kind == SVAssertionBinaryOperator::OverlappedImplication ||
          kind == SVAssertionBinaryOperator::NonOverlappedImplication)
        return fTrigger(regex, *consequent);
      return fNot(fTrigger(regex, fNot(*consequent)));
    }
    default:
      break;
    }
    FailureOr<int> left = buildProperty(operands.front());
    FailureOr<int> right = buildProperty(operands.back());
    if (failed(left) || failed(right))
      return failure();
    switch (kind) {
    case SVAssertionBinaryOperator::And:
      return fAnd({*left, *right});
    case SVAssertionBinaryOperator::Or:
      return fOr({*left, *right});
    case SVAssertionBinaryOperator::Implies:
      return fOr({fNot(*left), *right});
    case SVAssertionBinaryOperator::Iff:
      return fOr({fAnd({*left, *right}), fAnd({fNot(*left), fNot(*right)})});
    case SVAssertionBinaryOperator::Until:
      return intern({FK::Until, *left, *right, 0});
    case SVAssertionBinaryOperator::SUntil:
      return intern({FK::Until, *left, *right, 1});
    case SVAssertionBinaryOperator::UntilWith:
      return intern({FK::Until, *left, *right, 2});
    case SVAssertionBinaryOperator::SUntilWith:
      return intern({FK::Until, *left, *right, 3});
    default:
      return reject(binary, "this operator is not a property operator");
    }
  }
  return reject(operation, "this property operator is not supported by the "
                           "property automaton");
}

FailureOr<PropertyAutomaton> Compiler::compile(Operation *property) {
  FailureOr<int> initial = buildProperty(property);
  if (failed(initial))
    return failure();

  PropertyAutomaton result;
  std::map<std::tuple<int, int, int>, int> nodeIds;
  auto internNode = [&](int atom, int whenFalse, int whenTrue) {
    auto [found, inserted] = nodeIds.try_emplace(
        std::make_tuple(atom, whenFalse, whenTrue), result.nodes.size());
    if (inserted)
      result.nodes.push_back({atom, whenFalse, whenTrue});
    return found->second;
  };
  std::map<int, int> stateIds;
  std::vector<int> pending;
  auto targetOf = [&](int formula) {
    if (formula == pass)
      return PropertyAutomaton::kPass;
    if (formula == vacuous)
      return PropertyAutomaton::kVacuousPass;
    if (formula == fail)
      return PropertyAutomaton::kFail;
    auto [found, inserted] = stateIds.try_emplace(formula, stateIds.size());
    if (inserted)
      pending.push_back(formula);
    return found->second;
  };
  targetOf(*initial);
  // A property that decides nothing is an always passing or failing state.
  if (stateIds.empty())
    return reject(property, "property has a constant result");

  for (int atom : asyncAtoms)
    result.asyncAborts.push_back({atoms[atom], {}});

  size_t processed = 0;
  while (processed != pending.size()) {
    if (pending.size() > kMaxStates || result.nodes.size() > kMaxNodes)
      return reject(property, "property automaton exceeds its state limit");
    int formula = pending[processed++];
    SmallVector<int> stateAtoms;
    llvm::DenseSet<int> seen, visited;
    collectAtoms(formula, seen, visited, stateAtoms);
    llvm::sort(stateAtoms);
    if (stateAtoms.size() > kMaxAtomsPerState)
      return reject(property, "property automaton exceeds its Boolean limit");
    Valuation letter(atoms.size(), false);
    auto expand = [&](auto &&self, size_t depth) -> int {
      if (depth == stateAtoms.size())
        return internNode(-1, targetOf(step(formula, letter)), 0);
      letter[stateAtoms[depth]] = false;
      int whenFalse = self(self, depth + 1);
      letter[stateAtoms[depth]] = true;
      int whenTrue = self(self, depth + 1);
      return whenFalse == whenTrue
                 ? whenFalse
                 : internNode(stateAtoms[depth], whenFalse, whenTrue);
    };
    int root = expand(expand, 0);
    llvm::DenseSet<int> calls;
    result.states.push_back({root, passesAtEnd(formula, calls)});
    for (auto [atom, abort] : llvm::zip_equal(asyncAtoms, result.asyncAborts)) {
      int fired = fire(formula, atom);
      abort.targets.push_back(fired == formula ? PropertyAutomaton::kNoAbort
                                               : targetOf(fired));
    }
    if (invalid)
      return failure();
  }
  result.atoms = atoms;
  return result;
}

/// The operators the bounded monitor cannot place under another operator.
static bool hasNestedTemporal(Operation *operation,
                              SmallVectorImpl<StringRef> &active);

static bool isImplication(semantic::SVBinaryAssertionExprOp binary) {
  switch (binary.getOperatorKind()) {
  case SVAssertionBinaryOperator::OverlappedImplication:
  case SVAssertionBinaryOperator::NonOverlappedImplication:
  case SVAssertionBinaryOperator::OverlappedFollowedBy:
  case SVAssertionBinaryOperator::NonOverlappedFollowedBy:
    return true;
  default:
    return false;
  }
}

/// Walk one instance's expansion, and report a recursive instance.
static bool scanInstance(semantic::SVAssertionInstanceExpressionOp instance,
                         SmallVectorImpl<StringRef> &active,
                         llvm::function_ref<bool(Operation *)> scan) {
  StringRef path = instance.getReferencedPath();
  if (instance.getIsRecursiveProperty() || !instance.getHasExpandedBody() ||
      llvm::is_contained(active, path))
    return true;
  active.push_back(path);
  bool found = scan(getChildren(instance).front());
  active.pop_back();
  return found;
}

static bool hasNestedTemporal(Operation *operation,
                              SmallVectorImpl<StringRef> &active) {
  if (auto instance =
          dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation))
    return scanInstance(instance, active, [&](Operation *body) {
      return hasNestedTemporal(body, active);
    });
  if (isa<semantic::SVAbortAssertionExprOp,
          semantic::SVConditionalAssertionExprOp>(operation))
    return true;
  if (auto unary = dyn_cast<semantic::SVUnaryAssertionExprOp>(operation);
      unary && unary.getOperatorKind() == SVAssertionUnaryOperator::Not)
    return true;
  if (auto binary = dyn_cast<semantic::SVBinaryAssertionExprOp>(operation);
      binary && isImplication(binary))
    return true;
  for (Operation *child : getChildren(operation))
    if (isa<semantic::SVAssertionInstanceExpressionOp,
            semantic::SVSimpleAssertionExprOp, semantic::SVBinaryAssertionExprOp,
            semantic::SVUnaryAssertionExprOp,
            semantic::SVConditionalAssertionExprOp,
            semantic::SVAbortAssertionExprOp,
            semantic::SVStrongWeakAssertionExprOp,
            semantic::SVClockingAssertionExprOp>(child) &&
        hasNestedTemporal(child, active))
      return true;
  return false;
}

/// Same walk, only down the positions at the root of the property: instances
/// and clocking keep the root, and the first real operator decides.
static bool needsAutomatonAtRoot(Operation *operation,
                                 SmallVectorImpl<StringRef> &active) {
  if (auto instance =
          dyn_cast<semantic::SVAssertionInstanceExpressionOp>(operation))
    return scanInstance(instance, active, [&](Operation *body) {
      return needsAutomatonAtRoot(body, active);
    });
  if (auto simple = dyn_cast<semantic::SVSimpleAssertionExprOp>(operation)) {
    SmallVector<Operation *> children = getChildren(simple);
    return children.size() == 1 && !simple.getHasRepetition() &&
           isa<semantic::SVAssertionInstanceExpressionOp>(children.front()) &&
           needsAutomatonAtRoot(children.front(), active);
  }
  if (isa<semantic::SVClockingAssertionExprOp, semantic::SVDisableIffAssertionExprOp>(
          operation))
    return needsAutomatonAtRoot(getChildren(operation).back(), active);
  if (auto binary = dyn_cast<semantic::SVBinaryAssertionExprOp>(operation)) {
    SmallVector<Operation *> operands = getChildren(binary);
    if (operands.size() != 2)
      return false;
    // The consequent of an outermost implication, and any operand of a property
    // and/or, cannot nest these operators in the bounded monitor.
    if (isImplication(binary))
      return hasNestedTemporal(operands.back(), active);
    if (binary.getOperatorKind() == SVAssertionBinaryOperator::And ||
        binary.getOperatorKind() == SVAssertionBinaryOperator::Or) {
      auto temporal = [&](Operation *operand) {
        SmallVector<StringRef> scope(active.begin(), active.end());
        Operation *current = operand;
        while (auto simple =
                   dyn_cast<semantic::SVSimpleAssertionExprOp>(current)) {
          SmallVector<Operation *> nested = getChildren(simple);
          if (nested.size() != 1 ||
              !isa<semantic::SVAssertionInstanceExpressionOp>(nested.front()))
            return false;
          current = nested.front();
        }
        if (auto instance =
                dyn_cast<semantic::SVAssertionInstanceExpressionOp>(current))
          return scanInstance(instance, scope, [&](Operation *body) {
            return hasNestedTemporal(body, scope);
          });
        if (auto unary = dyn_cast<semantic::SVUnaryAssertionExprOp>(current);
            unary && unary.getOperatorKind() == SVAssertionUnaryOperator::Not)
          return false;
        return hasNestedTemporal(current, scope);
      };
      return temporal(operands.front()) || temporal(operands.back());
    }
    return false;
  }
  return false;
}

} // namespace

bool needsPropertyAutomaton(Operation *property) {
  SmallVector<StringRef> active;
  return needsAutomatonAtRoot(property, active);
}

FailureOr<PropertyAutomaton> compilePropertyAutomaton(
    Operation *property, bool strongSequences,
    llvm::function_ref<bool(Operation *)> sameClock) {
  return Compiler(strongSequences, sameClock).compile(property);
}

} // namespace talos::simlowering
