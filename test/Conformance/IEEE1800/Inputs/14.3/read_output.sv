module top;
  bit clk = 0;
  int value, r;
  clocking cb @(posedge clk);
    output value;
  endclocking
  initial r = cb.value;
endmodule
