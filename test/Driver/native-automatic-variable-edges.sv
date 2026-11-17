// RUN: talos %s -o %t.exe && %t.exe | FileCheck %s

// Threads forked by a task wait for edges of the task's automatic variable.
// An edge of a vector is an edge of its least significant bit, and any change
// of value, including to and from x or z, is a change (IEEE 1800-2023 9.4.2,
// Table 9-2). Each store publishes one transition of the whole variable.
// CHECK: rising=2 falling=2 changes=7
module top;
  int rising, falling, changes;
  task automatic run();
    logic [7:0] v = 8'h00;
    fork
      forever @(posedge v) rising++;
      forever @(negedge v) falling++;
      forever @(v) changes++;
    join_none
    #1 v = 8'h01;
    #1 v = 8'h03;
    #1 v = 8'h02;
    #1 v = 8'hx0;
    #1 v = 8'h01;
    #1 v = 8'hz1;
    #1 v = 8'h00;
    #1;
    disable fork;
  endtask
  initial begin
    run();
    $display("rising=%0d falling=%0d changes=%0d", rising, falling, changes);
  end
endmodule
