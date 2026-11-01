module top;
  struct {bit a[$]; shortint b;} a = '{'{0, 1, 0, 1}, 67};
  int b;
  initial b = int'(a);
endmodule
