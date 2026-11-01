module top;
  int a;
  function automatic void f(const ref int x);
    x = 3;
  endfunction
  initial f(a);
endmodule
