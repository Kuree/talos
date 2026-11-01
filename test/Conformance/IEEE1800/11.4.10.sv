// CLAUSE: sizing shift unsigned context
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.4.10: >>> keeps the sign only in a signed context, << and >> fill zeros, an X shift count gives X.
// CHECK: alone=fc mixed=04
// CHECK: shl=c4 shr=2c ashr=c0 lshr=40
// CHECK: xcount=xxxxxxxx

module top;
  logic signed [3:0] s;  logic [7:0] u, alone, mixed, a, b, c, d, e;
  logic signed [7:0] t;
  logic x = 1'bx;
  initial begin
    s = -8; u = 0;
    alone = s >>> 1;  mixed = (s >>> 1) + u;
    a = 8'b1011_0001; b = a << 2;  c = a >> 2;
    t = 8'sb1000_0001;  d = t >>> 1;  e = t >> 1;
    $display("alone=%h mixed=%h", alone, mixed);
    $display("shl=%h shr=%h ashr=%h lshr=%h", b, c, d, e);
    $display("xcount=%b", a << x);
  end
endmodule
