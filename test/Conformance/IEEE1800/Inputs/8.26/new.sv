interface class I;
  pure virtual function int f();
endclass
module top;
  I i;
  initial i = new;
endmodule
