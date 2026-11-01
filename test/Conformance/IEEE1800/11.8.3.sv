// CLAUSE: two bit top set
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.8.3: extension follows the RHS signedness (not the LHS), and a mixed expression is unsigned.
// CHECK: a=fa b=fa c=0a d=0a e=14 f=f4

module top;
  logic signed [3:0] sn = 4'sb1010;  logic [3:0] un = 4'b1010;
  logic signed [7:0] a, d, f;  logic [7:0] b, c, e;
  initial begin
    a = sn; b = sn; c = un; d = un; e = sn + un; f = sn + sn;
    $display("a=%h b=%h c=%h d=%h e=%h f=%h", a, b, c, d, e, f);
  end
endmodule
