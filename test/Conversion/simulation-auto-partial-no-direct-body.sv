// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto timing=true fallback-report=true' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s --check-prefix=FALLBACK < %t.trace
// RUN: FileCheck %s < %t.mlir

// A concurrent assertion is an Observed-region process that forks its failure
// report (IEEE 1800-2023 16.14.1), and the global-clock always_ff stages an NBA
// (4.4). The partial island has no direct body for the assertion's wait, so
// Auto must fall back before static NBA staging instead of failing late.
// TRACE: partial eval disabled: fanout owner without a direct body
// The fallback report lists every such owner, not only the first.
// FALLBACK: talos fallback: {"detail":"continuation={{[0-9]+}}","kind":"eval-disabled","loc":"{{.*}}.sv:25:3","owner":"{{unit_[0-9]+}}","reason":"fanout-owner-without-direct-body"}
// FALLBACK: talos fallback: {"detail":"continuation={{[0-9]+}}","kind":"eval-disabled","loc":"{{.*}}.sv:26:3","owner":"{{unit_[0-9]+}}","reason":"fanout-owner-without-direct-body"}
// The design-wide outcome: Auto keeps the generic scheduler.
// FALLBACK: talos fallback: {"detail":"bytecode-fanout-owner","kind":"aot-disabled","loc":"{{.*}}","reason":"partial-auto-fallback"}
// FALLBACK-NOT: talos fallback:
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
