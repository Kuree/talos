virtual class A;
  pure virtual function int get();
endclass
module top;
  A a;
  initial a = new;
endmodule
