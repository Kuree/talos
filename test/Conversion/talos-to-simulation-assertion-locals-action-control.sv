// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 20.11: $assertvacuousoff, $assertpassoff and $assertfailoff
// apply to an assertion with a local variable that finishes on the tick it
// starts. The monitor reads the action state once per tick and gates each
// report by class: a mismatching antecedent is a vacuous pass, a matched
// attempt a nonvacuous pass, a failing consequent a fail.
// CHECK-LABEL: simulation.func private @unit_0(
// CHECK: simulation.assert.action_state
// CHECK: arith.andi {{.*}} {simulation.concurrent_action_class = "vacuous-pass"
// CHECK: arith.andi {{.*}} {simulation.concurrent_action_class = "fail"
// CHECK: arith.andi %{{.*}}, %c1_i32{{.*}} : i32
// CHECK: arith.cmpi ne
// CHECK-NEXT: cf.cond_br
module top(input var logic clk, input var logic a, input var int d,
           input var int b);
  property p;
    int v;
    (a, v = d) |-> b == v;
  endproperty
  all: assert property (@(posedge clk) p) $info("pass"); else $info("fail");
  initial $assertvacuousoff(0, all);
endmodule
