// CLAUSE: sizing concat selfdetermined
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.6.1: a concatenation is unsigned and self-determined, so {a+b} wraps at 4 bits while a+b in an 8-bit context does not.
// CHECK: x=0f y=00 z=10 bits=4

module top;
  logic signed [3:0] s;  logic [3:0] a, b;  logic [7:0] x, y, z;
  initial begin
    s = -1; a = 15; b = 1;
    x = {s};  y = {a + b};  z = a + b;
    $display("x=%h y=%h z=%h bits=%0d", x, y, z, $bits({a + b}));
  end
endmodule
