module top;
  bit clk, a;
  assert property (@(posedge clk) ((1'b1) intersect (1'b1 ##1 1'b1)) |-> a);
endmodule
