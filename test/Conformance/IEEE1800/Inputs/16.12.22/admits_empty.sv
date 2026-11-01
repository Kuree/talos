module top;
  bit clk, a;
  assert property (@(posedge clk) a[*0:2]);
endmodule
