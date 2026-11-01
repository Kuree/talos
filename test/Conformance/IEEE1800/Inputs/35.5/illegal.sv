module top;
  import "DPI-C" function int f(ref int value);
  int a;
  initial $display("%0d", f(a));
endmodule
