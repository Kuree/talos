module top;
  logic a, b;
  initial @((a = b)) $finish;
endmodule
