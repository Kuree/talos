module top;
  bit clk, a;
  assert property (@(posedge clk) (a and 1'b0) |=> a);
endmodule
