module top;
  bit clk = 0;
  int data;
  clocking cb @(posedge clk);
    output data;
  endclocking
  initial cb.data <= #4 3;
endmodule
