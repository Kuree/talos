// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.9.1: a continuous assignment re-evaluates whenever any operand changes.
// CHECK: 1 w=0
// CHECK: 2 w=1
// CHECK: 3 w=0

module top;
  logic a, b;  wire w = a & b;
  initial begin
    a = 1; b = 0; #1; $display("1 w=%b", w);
    b = 1; #1; $display("2 w=%b", w);
    a = 0; #1; $display("3 w=%b", w);
  end
endmodule
