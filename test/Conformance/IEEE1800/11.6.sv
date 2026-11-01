// CLAUSE: self determined expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.6: expression width is max of operands (and of the comparison operands), but a concatenation fixes it at 6 bits.
// CHECK: bits=6 ctx=1 self=0

module top;
  logic [3:0] a = 15;  logic [5:0] b = 10;
  logic eq_ctx, eq_self;
  initial begin
    eq_ctx = (a * b == 16'd150);  eq_self = ({a * b} == 16'd150);
    $display("bits=%0d ctx=%b self=%b", $bits(a * b), eq_ctx, eq_self);
  end
endmodule
