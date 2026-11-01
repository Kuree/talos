// CLAUSE: interconnect wire control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.9.6: output and input ports carry values across the boundary, and an inout is one net seen identically on both sides (conflict gives x, then the child wins).
// CHECK: A n=1 m=0 pad=1 seen=1
// CHECK: B pad=x seen=x
// CHECK: C pad=0 seen=0

module drv (output wire value); assign value = 1'b1; endmodule
module sink (input wire v, output wire o); assign o = ~v; endmodule
module bidir (inout wire p, output wire seen, input wire en);
  assign p = en ? 1'b0 : 1'bz;  assign seen = p;
endmodule
module top;
  wire n, m, pad, seen;  logic en = 0, ext = 1;
  drv d(n);  sink s(n, m);
  assign pad = ext ? 1'b1 : 1'bz;
  bidir b(pad, seen, en);
  initial begin
    #1; $display("A n=%b m=%b pad=%b seen=%b", n, m, pad, seen);
    en = 1; #1; $display("B pad=%b seen=%b", pad, seen);
    ext = 0; #1; $display("C pad=%b seen=%b", pad, seen);
  end
endmodule
