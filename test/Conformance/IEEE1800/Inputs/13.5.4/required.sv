module top;
  task automatic consume(int a = 1, int b); endtask
  initial consume(.a(2));
endmodule
