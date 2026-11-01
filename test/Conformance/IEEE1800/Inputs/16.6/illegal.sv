// 16.6: evaluation of an expression in a concurrent assertion shall not have side effects.
module top;
  bit clk; int n;
  assert property (@(posedge clk) n++);
endmodule
