// CLAUSE: sizing mixed sign unsigned
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.4.3.1: a signed operand mixed with an unsigned one is zero-extended; / truncates toward zero, % takes the first operand sign.
// CHECK: mixed=15 signed=-4
// CHECK: div=-3 mod=-1 mod2=1

module top;
  logic signed [3:0] s;  logic [7:0] u, both;  logic signed [7:0] ss;
  int q, r, r2;
  initial begin
    s = -2; u = 1;
    both = s + u;  ss = s + s;
    q = -7 / 2;  r = -7 % 2;  r2 = 7 % -2;
    $display("mixed=%0d signed=%0d", both, ss);
    $display("div=%0d mod=%0d mod2=%0d", q, r, r2);
  end
endmodule
