class A;
  function new();
    #1;
  endfunction
endclass
module top;
  A a;
  initial a = new;
endmodule
