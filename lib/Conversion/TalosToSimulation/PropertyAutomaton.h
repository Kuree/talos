//===- PropertyAutomaton.h - Deterministic automaton of an SVA property ---===//
//
// The bounded concurrent monitor handles the common property shapes directly.
// A property nesting implications, negations, aborts or recursive instances
// compiles instead to a deterministic automaton over its Boolean atoms. Each
// live attempt is one count in the state it has reached, so attempts in the same
// state advance together, and one tick steps every state once.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_LIB_CONVERSION_TALOSTOSIMULATION_PROPERTYAUTOMATON_H
#define TALOS_LIB_CONVERSION_TALOSTOSIMULATION_PROPERTYAUTOMATON_H

#include "mlir/IR/Operation.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace talos::simlowering {

struct PropertyAutomaton {
  /// Outcomes of a step, as a leaf target; a nonnegative target is a state.
  static constexpr int kPass = -1;
  static constexpr int kVacuousPass = -2;
  static constexpr int kFail = -3;

  /// One decision on an atom's sampled truth, or with a negative `atom` a leaf
  /// whose `whenFalse` is the target. Shared between states.
  struct Node {
    int atom;
    int whenFalse;
    int whenTrue;
  };
  struct State {
    int root;
    /// The result of an attempt still in this state when the run ends.
    bool passesAtEnd;
  };

  /// IEEE 1800-2023 16.12.14: an asynchronous abort condition acts in any time
  /// step, not just at a tick. `targets` gives, per state, where its attempts go
  /// when the condition becomes true, or kNoAbort when they do not depend on it.
  static constexpr int kNoAbort = -4;
  struct AsyncAbort {
    mlir::Operation *condition;
    llvm::SmallVector<int> targets;
  };

  llvm::SmallVector<mlir::Operation *> atoms;
  llvm::SmallVector<AsyncAbort> asyncAborts;
  llvm::SmallVector<Node> nodes;
  /// State 0 is the property about to be evaluated, where an attempt starts.
  llvm::SmallVector<State> states;
};

/// Whether `property` has a shape only this automaton executes. Every other
/// property keeps the bounded monitor, so its cost and behavior do not change.
bool needsPropertyAutomaton(mlir::Operation *property);

/// Compile `property`. Sequences used directly as properties are strong when
/// `strongSequences`, per IEEE 1800-2023 16.12.2. `sameClock` tells whether a
/// nested clocking event is the clock of the assertion.
mlir::FailureOr<PropertyAutomaton> compilePropertyAutomaton(
    mlir::Operation *property, bool strongSequences,
    llvm::function_ref<bool(mlir::Operation *)> sameClock);

} // namespace talos::simlowering

#endif
