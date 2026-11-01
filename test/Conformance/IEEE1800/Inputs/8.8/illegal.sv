class A;
endclass
class B;
endclass
module top;
  A a;
  initial a = B::new;
endmodule
