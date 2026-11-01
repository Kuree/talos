module top;
  function automatic int f();
    #1;
    return 1;
  endfunction
  initial $display("%0d", f());
endmodule
