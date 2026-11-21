//===- EvalRoles.h - Roles of generated functions ---------------*- C++ -*-===//
//
// A generated function states its roles in `schedule.eval.role`. Consumers
// test the attribute instead of the symbol name, so renaming a function or
// deriving a new one (variants, wrappers, segments, partitions) cannot change
// which policy applies to it.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_SCHEDULE_EVALROLES_H
#define TALOS_DIALECT_SCHEDULE_EVALROLES_H

#include "talos/Dialect/Schedule/ScheduleEnums.h"

namespace mlir {
class Operation;
} // namespace mlir

namespace talos::schedule {

/// The origin roles: those a function made from another function's code
/// inherits (see EvalRoleEnum).
inline constexpr EvalRole inheritedEvalRoles =
    EvalRole::ClockedKernel | EvalRole::FusedKernel | EvalRole::EvalBody |
    EvalRole::WriteGuard | EvalRole::Dispatch;

/// The roles of a function; none without the attribute.
EvalRole getEvalRoles(mlir::Operation *function);

/// Whether the function holds every role in `roles` (at least one).
bool hasEvalRoles(mlir::Operation *function, EvalRole roles);

/// Adds `roles` to the roles of the function.
void addEvalRoles(mlir::Operation *function, EvalRole roles);

/// Gives `derived`, a function made from the code of `source`, the origin
/// roles of `source`.
void inheritEvalRoles(mlir::Operation *source, mlir::Operation *derived);

} // namespace talos::schedule

#endif // TALOS_DIALECT_SCHEDULE_EVALROLES_H
