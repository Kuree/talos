module top;
  bit clk, data;
  clocking cb @(posedge clk); input #0 data; endclocking
  a: assert property (@(posedge clk) cb.data);
endmodule
