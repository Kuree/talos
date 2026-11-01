// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 F.3.1: an assertion clock "e1 or e2" ticks when any member
// event occurs. The monitor suspends once on both members, with their own
// edges, and samples the property at each wake.
// CHECK-LABEL: simulation.func private @unit_0(
// CHECK: simulation.suspend.any %arg1, %arg2 edges [1, 2]
// CHECK: simulation.assert.sampled_read
// CHECK-LABEL: simulation.func private @unit_1(
// CHECK: simulation.suspend.any %arg1, %arg2 edges [1, 1]
module top(input var logic clk, input var logic other, input var logic a);
  cover property (@(posedge clk or negedge other) a) $info("or");
  cover property (@(posedge clk, posedge other) a) $info("comma");
endmodule
