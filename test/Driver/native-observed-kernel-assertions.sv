// RUN: talos --mlir-timing %s -o %t.exe 2> %t.log
// RUN: FileCheck %s --check-prefix=KERNEL < %t.log
// RUN: %t.exe | FileCheck %s

// Both assertions resume on the same clock edge in the Observed region
// (IEEE 1800-2023 4.4.2.5), so they run as one process. Each keeps its own
// attempts: `disable iff` discards only the first one's during reset
// (16.12), and $assertkill (20.11) kills the second one's pending attempt.
// The counts equal those of separate processes and of the bytecode tier.
// KERNEL: talos observed kernel: __talos_observed_{{[0-9_]+}} members=2
// CHECK: fail_reset=2 fail_next=2 pass_next=3
module top;
  bit clk, rst, a, b;
  int fail_reset, fail_next, pass_next;
  assert property (@(posedge clk) disable iff (rst) a |-> b) else fail_reset++;
  assert property (@(posedge clk) a |=> b) pass_next++; else fail_next++;
  task automatic tick(input bit va, input bit vb);
    a = va; b = vb;
    #1 clk = 1;
    #1 clk = 0;
  endtask
  initial begin
    rst = 1;
    tick(1, 0);
    tick(1, 0);
    rst = 0;
    tick(1, 1);
    tick(1, 0);
    tick(0, 1);
    tick(1, 0);
    $assertkill;
    tick(0, 0);
    tick(1, 1);
    tick(0, 1);
    #1;
    $display("fail_reset=%0d fail_next=%0d pass_next=%0d", fail_reset,
             fail_next, pass_next);
    $finish;
  end
endmodule
