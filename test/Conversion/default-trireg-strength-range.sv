// RUN: talos -emit-slang %s | FileCheck %s
// RUN: not talos -emit-slang -DABOVE %s 2>&1 | FileCheck %s --check-prefix=ABOVE
// RUN: not talos -emit-slang -DFAR_ABOVE %s 2>&1 | FileCheck %s --check-prefix=FAR

// IEEE 1800-2023 E.3: "The integer constant shall be between 0 and 250."
`default_trireg_strength 0
module low; endmodule
`default_trireg_strength 250
module high; endmodule
`ifdef ABOVE
`default_trireg_strength 251
module above; endmodule
`endif
`ifdef FAR_ABOVE
`default_trireg_strength 100000
module far_above; endmodule
`endif

// CHECK: low
// CHECK: high
// ABOVE: error: `default_trireg_strength must be between 0 and 250
// FAR: error: `default_trireg_strength must be between 0 and 250
