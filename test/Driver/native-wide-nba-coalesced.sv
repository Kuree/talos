// RUN: talos -O3 --vpi=off --native-scheduler=eval --mlir-timing %s -o %t.four 2> %t.plan
// RUN: FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t.four | FileCheck %s
// RUN: talos -O3 --vpi=off --native-scheduler=eval --two-state %s -o %t.two
// RUN: %t.two | FileCheck %s
// RUN: talos -O3 --vpi=off --native-scheduler=eval -emit-llvm %s -o %t.ll
// RUN: FileCheck %s --check-prefix=IR --implicit-check-not=__talos_eval_ordered_nba_queue_v1 --implicit-check-not=talos_rt_v1_eval_nba_reserve < %t.ll
// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval' | FileCheck %s --check-prefix=SUMMARY

// IEEE 1800-2023 4.3, 4.6(b), 4.9.4, 9.2.2.3 and 10.4.2: repeated
// whole-root NBA captures may retain the last value when intermediate values
// have no observers. The latch still samples in Active, publishes in NBA,
// follows data while open and holds it while closed. This is a 195-bit bank,
// not an edge-triggered approximation. The X -> known and known -> X sequences
// can select different four-state/two-state implementations in one NBA window;
// they must overwrite one shared capture. A capture equal to current state
// must still overwrite a different pending value.
//
// A change observer distinguishes the intermediate updates even when the
// final value equals the incoming value. With OBSERVE it retains the queue.

// PLAN: talos eval coalesced whole-root NBA: roots=1
// CHECK: {{^}}PASS{{$}}
// IR: define {{.*}}void @unit_{{[0-9]+}}.__talos_eval_body_0(
// The known-value guard shares the barrier's summary; its work must not
// grow with the number of fixed chunks.
// SUMMARY-LABEL: llvm.func internal @__talos_eval_nba_known_v1(
// SUMMARY-NOT: @__talos_eval_nba_valid_
// SUMMARY: llvm.mlir.addressof @__talos_eval_nba_dynamic_pending_v1
// SUMMARY-NOT: @__talos_eval_nba_valid_
// SUMMARY: llvm.cond_br
// SUMMARY-NOT: @__talos_eval_nba_valid_
// SUMMARY: llvm.return

module native_wide_nba_coalesced;
  bit clk = 0;
  logic [194:0] data = '0;
  logic [194:0] held = '0;
  always #5 clk = ~clk;
  always_latch if (clk) held <= data;

`ifdef OBSERVE
  int wakes = 0;
  always @(held) wakes++;
`endif

  initial begin
    #6;
    data = 'x;
    #0;
    data = '1;
    #0;
    if (held !== 195'b0) $fatal(1, "published before NBA");
    data = '0;
    #1;
    if (held !== 195'b0) $fatal(1, "pending overwrite lost");
`ifdef OBSERVE
    if (wakes != 1) $fatal(1, "intermediate change lost: %0d", wakes);
`endif
    data = '1;
    #0;
    data = 'x;
    #0;
    if (held !== 195'b0) $fatal(1, "variant published before NBA");
    #1;
    if (held !== {195{1'bx}}) $fatal(1, "unknown plane lost");
    data = '1;
    #1;
    if (held !== {195{1'b1}}) $fatal(1, "known value after X lost");
    data = 'z;
    #1;
    if (held !== {195{1'bz}}) $fatal(1, "high impedance plane lost");
    #2;
    data = 195'h123;
    #1;
    if (held !== {195{1'bz}}) $fatal(1, "closed latch changed");
    #4;
    if (held !== 195'h123) $fatal(1, "opening copy lost");
    $display("PASS");
    $finish;
  end
endmodule
