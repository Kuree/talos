module top;
  M n();
endmodule
module M;
  parameter p = 2;
  defparam top.n.p = 1;
  if (p == 1) begin : top
    N n();
  end
endmodule
module N;
  parameter p = 3;
endmodule
