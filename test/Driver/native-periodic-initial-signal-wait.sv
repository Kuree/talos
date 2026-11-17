// RUN: talos -O3 %s -o %t
// RUN: %t | FileCheck %s

// Once-reached and repeat waits of an initial procedure on a generated root
// that is not a periodic clock. Periodic preparation drains only waiters on
// periodic sources, and a generated store to `count` publishes no runtime
// wake, so these waits must keep a generated executor or the generic route
// (IEEE 1800-2023 9.2.1, 9.4.2); either way each sees its edge.
module native_periodic_initial_signal_wait;
  logic clk = 0;
  logic [7:0] count = 0;
  logic once = 0, twice = 0;
  initial forever #5 clk = ~clk;
  always @(posedge clk) count <= count + 1;
  initial begin
    #100;
    @(posedge count[2]);
    once = 1;
  end
  initial begin
    #100;
    repeat (2) @(posedge count[1]);
    twice = 1;
  end
  initial begin
    #300;
    $display("count=%0d once=%b twice=%b", count, once, twice);
    $finish;
  end
endmodule

// CHECK: count=30 once=1 twice=1
