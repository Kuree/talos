module top;
  struct {bit [7:0] a; shortint b;} a;
  int b;
  initial b = int'(a);
endmodule
