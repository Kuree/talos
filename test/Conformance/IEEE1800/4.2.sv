// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.2: update events of nonblocking assignments are applied after all evaluation events of the edge, so q2 sees the old q1.
// CHECK: after1 q1=1 q2=0
// CHECK: after2 q1=1 q2=1

module top;
  bit clk, d;  bit q1, q2;
  always @(posedge clk) q1 <= d;
  always @(posedge clk) q2 <= q1;
  initial begin
    d = 1;
    #1 clk = 1; #1 clk = 0; $display("after1 q1=%b q2=%b", q1, q2);
    #1 clk = 1; #1 clk = 0; $display("after2 q1=%b q2=%b", q1, q2);
  end
endmodule
