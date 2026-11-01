module top;
  task automatic t();
    fork
      return;
    join_none
  endtask
  initial t();
endmodule
