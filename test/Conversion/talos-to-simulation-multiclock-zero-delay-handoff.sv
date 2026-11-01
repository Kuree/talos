// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--test-talos-set-module-attributes=attrs="{llvm.data_layout = \"e-m:e-p:64:64-i64:64-n8:16:32:64-S128\", llvm.target_triple = \"x86_64-unknown-linux-gnu\"}"' -o %t.talos.mlir
// RUN: talos-opt %t.talos.mlir '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 16.13.1: ##0 into another clock moves to the nearest possibly
// overlapping tick of that clock: it stays in the cohort when both clocks tick
// together and otherwise waits for the next tick, like ##1. The attempt that
// has to wait is held in a token count that the clock suspension carries as
// an extra operand; a ##0 that had to coincide would keep none.
// CHECK-LABEL: simulation.func private @unit_0(
// CHECK-SAME: simulation.multiclock_sequence_coordinator
// CHECK: simulation.suspend.clock_set %arg1, %arg2, {{%[0-9]+}} conditions 0 edges [1, 1]
module top(input var logic c1, input var logic c2, input var logic a,
           input var logic b);
  cover property (@(posedge c1) a ##0 @(posedge c2) b) $info("hit");
endmodule
