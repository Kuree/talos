//===- TalosDialect.td - Talos semantic dialect -------*- tablegen -*-===//
//
// Talos's semantic IR preserves the elaborated Slang AST and provides typed
// operations for SystemVerilog values, storage, processes and runtime services.
// Talos-to-Simulation lowering makes execution and scheduling effects explicit.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_TALOS_TALOSDIALECT_TD
#define TALOS_DIALECT_TALOS_TALOSDIALECT_TD

include "mlir/IR/DialectBase.td"

def TalosDialect : Dialect {
  let name = "talos";
  let cppNamespace = "::talos::ir";

  let summary = "Elaborated SystemVerilog semantics";
  let description = [{
    `talos` receives the elaborated `slang` dialect. Its `talos.sv.*`
    operations preserve source identity, resolved references, declared types,
    and hierarchy as an attribute-and-region tree. It also defines typed
    semantic operations for four-state values, references and nets, processes,
    classes, containers, randomization, and runtime services.

    Talos-to-Simulation lowering produces the executable `simulation`
    dialect, with isolated SSA code units, explicit effects, and flattened
    design descriptors. Source AST operations are eliminated at that boundary.
  }];

  // Enum attributes are specialized builtin IntegerAttr wrappers, so the
  // dialect has no standalone `#talos.*` attributes to parse.
  let useDefaultAttributePrinterParser = 0;
  let useDefaultTypePrinterParser = 1;
  // Preserve standard SymbolTable interoperability across textual round trips.
  let usePropertiesForAttributes = 0;
}

#endif // TALOS_DIALECT_TALOS_TALOSDIALECT_TD
