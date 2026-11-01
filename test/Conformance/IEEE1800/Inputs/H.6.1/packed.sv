module top;
  import "DPI-C" function void f(input bit [15:8] b[]);
  bit [3:0] a[2];
  initial f(a);
endmodule
