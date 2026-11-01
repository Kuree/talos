module top;
  bit c;
  int out;
  always_ff @(posedge c) out <= 1;
  initial out = 2;
endmodule
