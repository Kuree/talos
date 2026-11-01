module top;
  timeunit 1ns; timeprecision 1ns;
  int n = 0;
  final $display("final n=%0d t=%0t", n, $time);
  initial #4 n = 7;
endmodule
