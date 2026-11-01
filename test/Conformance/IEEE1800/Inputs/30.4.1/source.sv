module cell_t(input wire a, output wire y);
  timeunit 1ns; timeprecision 1ps;
  wire internal = a;
  assign y = internal;
  specify (internal => y) = 2; endspecify
endmodule
module top;
  timeunit 1ns; timeprecision 1ps;
  logic a = 0;
  wire y;
  cell_t d(a, y);
endmodule
