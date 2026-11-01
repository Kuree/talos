// CLAUSE: signed part select
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.8.1: part-select, bit-select, concatenation and relational results are unsigned; the plain signed operand sign-extends.
// CHECK: p=00f0 q=fff0 r=00f0 bs=1 n4=1

module top;
  logic signed [7:0] b = 8'hf0;
  logic [15:0] p, q, r;  int bs;  logic [3:0] n4;
  initial begin
    p = b[7:0];  q = b;  r = {b};  bs = b[7];  n4 = (b < 0);
    $display("p=%h q=%h r=%h bs=%0d n4=%h", p, q, r, bs, n4);
  end
endmodule
