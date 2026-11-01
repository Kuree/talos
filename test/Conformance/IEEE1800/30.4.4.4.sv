// CLAUSE: ifnone conditional pair control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 30.4.4.4: while c is true the if(c) path delay 2 applies; with c false the ifnone path delay 3 does (output still old at +2.9, new at +3.1).
// CHECK: P1 early=0 late=1 P2 early=1 late=0

module cell_t (input wire a, c, output wire y);
  timeunit 1ns; timeprecision 100ps;
  assign y = a;
  specify if (c) (a => y) = 2; ifnone (a => y) = 3; endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 100ps;
  logic a = 0, c = 0;  wire y;  cell_t u(a, c, y);
  logic e1, l1, e2, l2;
  initial begin
    #10; c = 1; #1; a = 1; #1.9; e1 = y; #0.2; l1 = y;       // conditional path: delay 2
    #5; c = 0; #1; a = 0; #2.9; e2 = y; #0.2; l2 = y;       // ifnone path: delay 3
    $display("P1 early=%b late=%b P2 early=%b late=%b", e1, l1, e2, l2);
  end
endmodule
