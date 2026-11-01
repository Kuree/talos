module top;
  bit clk;
  assert property (@(posedge clk) 1'b1[*0]);
endmodule
