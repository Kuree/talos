module top;
  int a;
  function void f(ref int x);
    x = 3;
  endfunction
  initial f(a);
endmodule
