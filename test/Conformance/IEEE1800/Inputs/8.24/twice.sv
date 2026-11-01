class C;
  extern function int f();
endclass
function int C::f();
  return 1;
endfunction
function int C::f();
  return 2;
endfunction
module top;
endmodule
