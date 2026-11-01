// CLAUSE: Optional directives
// XFAIL: *
// The delay-mode directives are accepted but do not change which delay is used.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins Annex E: `delay_mode_path uses the specify path delay (2) and `delay_mode_distributed the assign delay (5) for otherwise identical modules.
// CHECK: E t=11.5 p=0 d=0 | t=12.5 p=1 d=0 | t=15.5 p=1 d=1

`delay_mode_path
module cpath (input a, output y);
  timeunit 1ns; timeprecision 100ps;
  assign #5 y = a;
  specify (a => y) = 2; endspecify
endmodule
`delay_mode_distributed
module cdist (input a, output y);
  timeunit 1ns; timeprecision 100ps;
  assign #5 y = a;
  specify (a => y) = 2; endspecify
endmodule
`resetall
module top;
  timeunit 1ns; timeprecision 100ps;
  logic a = 0;  wire yp, yd;  cpath p(a, yp);  cdist d(a, yd);
  logic p1, d1, p2, d2;
  initial begin
    #10 a = 1;
    #1.5 p1 = yp; d1 = yd;
    #1 p2 = yp; d2 = yd;
    #3 $display("E t=11.5 p=%b d=%b | t=12.5 p=%b d=%b | t=15.5 p=%b d=%b", p1, d1, p2, d2, yp, yd);
  end
endmodule
