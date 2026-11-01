module top;
  function automatic int fun(int j = 1, string s = "no");
    return j;
  endfunction
  initial void'(fun(.s("yes"), 2));
endmodule
