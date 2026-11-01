class C #(int N = 1);
endclass
module top;
  int x = C::N;
endmodule
