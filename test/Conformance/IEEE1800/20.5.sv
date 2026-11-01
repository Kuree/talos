// CLAUSE: real bit roundtrip
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 20.5: IEEE-754 bit patterns, exact round trips, and $rtoi truncation toward zero.
// CHECK: rb=3ff8000000000000 sb=40200000 back=1 1
// CHECK: rtoi=-3 3 itor=5.0

module top;
  real r;  shortreal s;  logic [63:0] rb;  logic [31:0] sb;  int a, b;  real c;
  initial begin
    r = 1.5; s = 2.5; rb = $realtobits(r); sb = $shortrealtobits(s);
    a = $rtoi(-3.9); b = $rtoi(3.9); c = $itor(5);
    $display("rb=%h sb=%h back=%b %b", rb, sb, $bitstoreal(rb) == r, $bitstoshortreal(sb) == s);
    $display("rtoi=%0d %0d itor=%0.1f", a, b, c);
  end
endmodule
