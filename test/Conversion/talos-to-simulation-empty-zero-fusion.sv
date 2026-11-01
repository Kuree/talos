// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 16.9.2.1: (empty ##0 seq) and (seq ##0 empty) do not match,
// so such an operand of an or contributes nothing and the monitor reads only
// the other operand.
// CHECK-LABEL: simulation.func private @unit_0(
// CHECK-COUNT-1: simulation.assert.sampled_read
// CHECK-NOT: simulation.assert.sampled_read
// CHECK-LABEL: simulation.func private @unit_1(
// CHECK-COUNT-1: simulation.assert.sampled_read
// CHECK-NOT: simulation.assert.sampled_read
module top(input var logic clk, input var logic x, input var logic y,
           input var logic c);
  cover property (@(posedge clk) (x[*0] ##0 y) or c) $info("empty first");
  cover property (@(posedge clk) (y ##0 x[*0]) or c) $info("empty last");
endmodule
