module top;
  int w = 2;
  logic [7:0] a, b;
  initial b = a[0+:w];
endmodule
