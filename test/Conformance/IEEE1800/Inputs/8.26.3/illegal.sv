interface class I;
  typedef int T;
  pure virtual function T f();
endclass
class C implements I;
  T value;
  virtual function I::T f();
    return value;
  endfunction
endclass
module top;
endmodule
