module top;
  bit clk = 0;
  int value;
  clocking cb @(posedge clk);
    input value;
  endclocking
  initial cb.value <= 7;
endmodule
