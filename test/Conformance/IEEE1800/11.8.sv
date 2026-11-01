// CLAUSE: Assignment context preserves arithmetic carry
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.8: operands are sized to the assignment context, so the carry survives in a 9-bit target and is lost in an 8-bit one.
// CHECK: sum=256 s8=0 carry=1

module top;
  logic [7:0] a = 255, b = 1, s8;  logic [8:0] sum;  logic carry;
  initial begin
    sum = a + b;  s8 = a + b;  {carry, s8} = a + b;
    $display("sum=%0d s8=%0d carry=%b", sum, s8, carry);
  end
endmodule
