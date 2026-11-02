//===- SDFDialect.td - Transient Standard Delay Format IR -*- tablegen -*-===//

#ifndef TALOS_DIALECT_SDF_SDFDIALECT_TD
#define TALOS_DIALECT_SDF_SDFDIALECT_TD

include "mlir/IR/DialectBase.td"

def TalosSDFDialect : Dialect {
  let name = "sdf";
  let cppNamespace = "::talos::sdf";
  let summary = "transient normalized IEEE 1800 Clause 32 data";
  let description = [{
    `sdf` represents parsed Standard Delay Format records from IEEE 1800
    Clause 32. A delay file contains cells with ordered path delays,
    interconnect and terminal delays, timing checks, labels, and pulse limits.
    Typed attributes preserve decimal values, min/typ/max alternatives,
    timescales, ports, and conditions until annotation resolves them.

    The SystemVerilog frontend applies these records to elaborated Clause 30
    and 31 timing metadata and erases the SDF operations before returning
    executable simulation IR.
  }];
  let useDefaultAttributePrinterParser = 1;
  let usePropertiesForAttributes = 0;
}

#endif // TALOS_DIALECT_SDF_SDFDIALECT_TD
