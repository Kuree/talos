// RUN: talos -O3 --vpi=off --native-scheduler=eval --dump-ir-after=materialize-native-eval-transactions --dump-ir-path=%t.bank.mlir %s && FileCheck %s --check-prefix=BANK < %t.bank.mlir
// RUN: talos -O3 --vpi=off --native-scheduler=eval %s -o %t.eval && %t.eval > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off --native-scheduler=eval %s -o %t.two && %t.two > %t.two.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 | diff -u %t.two.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval --nba-queue=generic %s -o %t.fifo && %t.fifo | diff -u %t.out -
// RUN: talos -O3 --vpi=off --native-scheduler=eval -G Width=65 --dump-ir-after=materialize-native-eval-transactions --dump-ir-path=%t.two-words.mlir %s && FileCheck %s --check-prefix=BANK < %t.two-words.mlir
// RUN: talos -O3 --vpi=off --native-scheduler=eval -G Width=65 %s -o %t.short && %t.short | FileCheck %s

// IEEE 1800-2023 4.6(b), 9.4.2, 10.4.2. Separate words of one complete
// assignment pulse and return to their old values before the change waiters
// resume. The last partial word also distinguishes an X from a Z.
// BANK: llvm.mlir.global internal @__talos_eval_nba_change_bank_[[ROOT:[0-9]+]].value()
// BANK: llvm.mlir.global internal @__talos_eval_nba_change_bank_[[ROOT]].unknown()
// BANK: llvm.mlir.global internal @__talos_eval_nba_change_bank_[[ROOT]].transient()
// BANK: llvm.mlir.global internal @__talos_eval_nba_change_bank_[[ROOT]].valid()
// CHECK: pulse 000 1 1 0
// CHECK-NEXT: unknown z 1 1 1
// CHECK-NEXT: end 1 x 2 1 2 0

module top #(parameter int Width = 321);
  localparam int Middle = Width > 130 ? 130 : Width/2;
  bit clk;
  logic rst_n = 0;
  logic [Width-1:0] q = '0, first = '0, last = '0;
  int low, middle, high, failures;
  always #5 clk = !clk;
  always @(posedge clk) begin
    q <= first;
    q <= last;
  end
  always @(q[2]) low++;
  always @(q[Middle]) middle++;
  always @(q[Width-1]) high++;
  a: assert property (@(posedge clk) disable iff (!rst_n) rst_n |=> rst_n) else failures++;
  initial begin
    #1 rst_n = 1;
    first[2] = 1;
    first[Middle] = 1;
    #5;
    $display("pulse %b%b%b %0d %0d %0d", q[2], q[Middle], q[Width-1], low, middle, high);
    first = '0;
    first[Width-1] = 1'bx;
    last[Width-1] = 1'bz;
    #10;
    $display("unknown %b %0d %0d %0d", q[Width-1], low, middle, high);
    first[2] = 1;
    last = first;
    #10;
    $display("end %b %b %0d %0d %0d %0d", q[2], q[Width-1], low, middle, high, failures);
    $finish;
  end
endmodule
