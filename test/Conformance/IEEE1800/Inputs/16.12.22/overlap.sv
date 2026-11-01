module top;
  bit clk, a;
  assert property (@(posedge clk) 1'b1[*0] |-> a);
endmodule
