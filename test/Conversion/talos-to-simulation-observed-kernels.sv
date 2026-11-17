// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=3' | FileCheck %s --check-prefix=FUSED
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=3 observed-kernels=false' | FileCheck %s --check-prefix=SEPARATE
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=3 vpi=read' | FileCheck %s --check-prefix=SEPARATE
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=SEPARATE

// Concurrent assertions on one clock evaluate in the Observed region
// (IEEE 1800-2023 4.4.2.5). From O1 with VPI off, they resume as one process,
// unless observed kernels are disabled. A VPI client can tell the processes
// apart, so VPI keeps them separate.
// FUSED: simulation.spawn @__talos_observed_
// FUSED: simulation.func private @__talos_observed_{{[0-9_]+}}(
// FUSED-SAME: home_region = 8
// FUSED-COUNT-1: simulation.suspend.edge posedge
// FUSED-NOT: simulation.suspend.edge posedge
// SEPARATE-NOT: __talos_observed_
// SEPARATE-COUNT-2: simulation.suspend.edge posedge
// SEPARATE-NOT: simulation.suspend.edge posedge
module top;
  bit clk, a, b;
  assert property (@(posedge clk) a |-> b);
  assert property (@(posedge clk) a |=> b);
endmodule
