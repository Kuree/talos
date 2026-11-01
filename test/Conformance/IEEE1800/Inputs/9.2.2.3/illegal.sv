module top;
  bit gate;
  int out;
  always_latch if (gate) #1 out = 7;
endmodule
