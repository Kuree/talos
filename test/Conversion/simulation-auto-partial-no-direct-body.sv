// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto timing=true' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s < %t.mlir

// A concurrent assertion is an Observed-region process that forks its failure
// report (IEEE 1800-2023 16.14.1), and the global-clock always_ff stages an NBA
// (4.4). The partial island has no direct body for the assertion's wait, so
// Auto must fall back before static NBA staging instead of failing late.
// TRACE: partial eval disabled: fanout owner without a direct body
// TRACE-NOT: partial eval ownership failed
// CHECK-NOT: __talos_eval_dispatch_v1

module partial_no_direct_body;
  bit clk = 0, f = 1;
  bit [2:0] c = 0;
  always #5 clk = ~clk;
  global clocking @(posedge clk); endclocking
  always_ff @($global_clock) c <= c + 1;
  assert property (@($global_clock) c == 7 |-> f);
  initial #100 $finish;
endmodule
