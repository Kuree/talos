// CLAUSE: Disabling only queued assertion A removes A while leaving queued B to mature and pass at t
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Resuming the process in the same time step flushes the instance it queued with sig=0, so only the sig=1 instance
// matures (glitch line). Without a second resume the sig=0 instance matures and fails. Disabling the queued label a
// removes a while queued b matures and passes.
// CHECK: glitch p=1 f=0
// CHECK: no glitch p=1 f=1
// CHECK: disabled a_failed=0 b_passed=1

module top;
  bit clk, sig = 1; int p, f, a_failed, b_passed;
  always @(sig) assert property (@(posedge clk) const'(sig)) p++; else f++;
  initial begin
    a: assert property (@(posedge clk) 0) else a_failed++;
    b: assert property (@(posedge clk) 1) b_passed++;
    disable a;
  end
  initial begin
    #1 clk = 1; sig = 0;
    #0 sig = 1;
    #1 clk = 0;
    $display("glitch p=%0d f=%0d", p, f);
    #1 clk = 1; sig = 0;
    #1 clk = 0;
    $display("no glitch p=%0d f=%0d", p, f);
    $display("disabled a_failed=%0d b_passed=%0d", a_failed, b_passed);
  end
endmodule
