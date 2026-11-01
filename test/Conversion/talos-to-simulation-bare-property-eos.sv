// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// A bare bounded property still pending when the run ends completes with its
// strength (IEEE 1800-2023 16.12.2, 16.12.11, F.3.4.3.1): a sequence is
// weak(sequence) in assert, an s_ operator is strong, a plain nexttime weak,
// and a cover sequence is strong, which runs no pass action.
// CHECK-LABEL: simulation.func private @unit_0.$concurrent_eos_report.{{[0-9]+}}.weak
// CHECK-LABEL: simulation.func private @unit_0(
// CHECK-SAME: simulation.end_of_simulation_strength = "weak"
// CHECK-LABEL: simulation.func private @unit_1.$concurrent_eos_report.{{[0-9]+}}.strong
// CHECK-LABEL: simulation.func private @unit_1(
// CHECK-SAME: simulation.end_of_simulation_strength = "strong"
// CHECK-LABEL: simulation.func private @unit_2.$concurrent_eos_report.{{[0-9]+}}.strong
// CHECK-LABEL: simulation.func private @unit_2(
// CHECK-SAME: simulation.end_of_simulation_strength = "strong"
// CHECK-LABEL: simulation.func private @unit_3.$concurrent_eos_report.{{[0-9]+}}.weak
// CHECK-LABEL: simulation.func private @unit_3(
// CHECK-SAME: simulation.end_of_simulation_strength = "weak"
// CHECK-LABEL: simulation.func private @unit_4(
// CHECK-SAME: simulation.end_of_simulation_strength = "strong"
module top(input var logic clk, input var logic a, input var logic b);
  assert property (@(posedge clk) a ##1 b) $display("p0");
  assert property (@(posedge clk) s_nexttime a) else $display("p1");
  assert property (@(posedge clk) s_eventually [1:2] b) else $display("p2");
  assert property (@(posedge clk) nexttime a) $display("p3");
  cover property (@(posedge clk) a ##1 b) $display("p4");
endmodule
