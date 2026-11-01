module top;
  task automatic rd(int j = 0, int k, int data = 1); endtask
  initial rd(1, , 7);
endmodule
