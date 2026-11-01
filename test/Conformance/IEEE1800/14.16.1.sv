// CLAUSE: single module clockvar strobe
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 14.16.1: a drive to an inout clockvar changes the signal but cb.a keeps the last sampled value until the next clocking event.
// CHECK: T2 a=5 cb.a=1 b=1
// CHECK: T3 cb.a=5

module top;
  bit clk;  int a = 1, b;
  clocking cb @(posedge clk); inout a; output b; endclocking
  initial begin #1 clk = 1; #1 clk = 0; #1 clk = 1; end
  initial begin
    @(cb);
    cb.a <= 5;  cb.b <= cb.a;          // 14.16.1 example
    #1; $display("T2 a=%0d cb.a=%0d b=%0d", a, cb.a, b);
    @(cb); $display("T3 cb.a=%0d", cb.a);
  end
endmodule
