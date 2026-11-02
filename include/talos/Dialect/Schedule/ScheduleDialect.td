#ifndef TALOS_DIALECT_SCHEDULE_DIALECT_TD
#define TALOS_DIALECT_SCHEDULE_DIALECT_TD
include "mlir/IR/DialectBase.td"
def ScheduleDialect : Dialect {
  let name = "schedule";
  let usePropertiesForAttributes = 0;
  let cppNamespace = "::talos::schedule";
  let summary = "Simulation execution plans and native scheduler actions";
  let description = [{
    `schedule` records effects, activation and ordering dependencies,
    continuation and timing sites, commit groups, convergence, and kernel
    ownership. Simulation-to-schedule derives these plans, scheduling
    transforms specialize them, and executor conversions consume them.

    Its operations represent native packed computations, continuous-transfer
    activations, pending activation sets, NBA commits, process controls, and
    suspension continuations. They retain the semantic facts needed by native
    lowering after simulation values and handles acquire physical layouts.
  }];
  let useDefaultAttributePrinterParser = 1;
  // Canonicalization of native predicates materializes arith constants.
  let dependentDialects = ["::mlir::arith::ArithDialect"];
}
#endif
