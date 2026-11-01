class C;
  local int v;
endclass
class D extends C;
  function int f();
    return v;
  endfunction
endclass
module top;
endmodule
