// CLAUSE: self determined expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.6.3: operands of a self-determined expression keep their own width (max(4,6)=6, 150 mod 64 = 22), unlike the assignment context.
// CHECK: self=22 context=150

module top;
  logic [3:0] a = 15;  logic [5:0] b = 10;  logic [15:0] v, w;
  initial begin
    v = {a * b};  w = a * b;
    $display("self=%0d context=%0d", v, w);
  end
endmodule
