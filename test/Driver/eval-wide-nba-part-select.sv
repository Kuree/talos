// RUN: talos -O3 --vpi=off --native-scheduler=eval --dump-ir-after=materialize-native-eval-transactions --dump-ir-path=%t.bank.mlir %s
// RUN: FileCheck %s --check-prefix=BANK < %t.bank.mlir
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref > %t.out && FileCheck %s < %t.out
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.eval && %t.eval | diff -u %t.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.fifo && %t.fifo | diff -u %t.out -
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 > %t.two.out
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval %s -o %t.two && %t.two | diff -u %t.two.out -

// The original RHS and index are captured in Active. Both overlapping
// updates occur in NBA, including a pulse that returns to the old value.
// The next wait on one slice must ignore changes on disjoint slices.
// IEEE 1800-2023 4.6(b), 9.4.2, 10.4.2, 11.5.1.
// BANK-NOT: llvm.mlir.global internal @__talos_eval_nba_change_bank_
// BANK: llvm.call @talos_rt_v1_scheduler_packed_slice_nba(
// BANK-NOT: llvm.mlir.global internal @__talos_eval_nba_change_bank_
// CHECK: cross 00 5 1 1 0
// CHECK-NEXT: top z 5 1 1 1
// CHECK-NEXT: bottom 3 5 1 1 1 0
module top #(parameter int Width = 521);
  bit clk;
  logic rst_n = 0;
  logic [Width-1:0] q = '0;
  int lowIndex, highIndex;
  logic [8:0] a, b;
  int bit63, bit64, topBit, failures;

  always #5 clk = !clk;
  always @(posedge clk) begin
    q[lowIndex +: 9] <= a;
    q[highIndex +: 9] <= b;
  end
  always @(q[63]) bit63++;
  always @(q[64]) bit64++;
  always @(q[Width-1]) topBit++;
  a_reset: assert property (@(posedge clk) disable iff (!rst_n) rst_n |=> rst_n)
    else failures++;

  initial begin
    #1 rst_n = 1;
    lowIndex = 61; highIndex = 63;
    a = '1; b = 9'h054;
    #5;
    $display("cross %b%b %h %0d %0d %0d", q[64], q[63], q[70:67], bit63, bit64, topBit);
    lowIndex = Width-1; highIndex = Width-1;
    a = 'x; b = 'z;
    #10;
    $display("top %b %h %0d %0d %0d", q[Width-1], q[70:67], bit63, bit64, topBit);
    lowIndex = -3; highIndex = Width+7;
    a = 9'h018; b = '0;
    #10;
    $display("bottom %h %h %0d %0d %0d %0d", q[3:0], q[70:67], bit63, bit64, topBit, failures);
    $finish;
  end
endmodule
