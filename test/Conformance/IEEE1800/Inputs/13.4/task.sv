module top;
  task t(); endtask
  function automatic int f();
    t();
    return 1;
  endfunction
  initial $display("%0d", f());
endmodule
