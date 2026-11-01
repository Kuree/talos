// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.3: only a real change of the net value is an update event that wakes the @(w) process (a=3 twice gives one wake, a=5 another).
// CHECK: cnt=2 w=6

module top;
  int a;  wire [31:0] w = a + 1;  int cnt;
  initial begin #1; forever begin @(w); cnt++; end end
  initial begin
    #2 a = 3;  #1 a = 3;  #1 a = 5;  #1;
    $display("cnt=%0d w=%0d", cnt, w);
  end
endmodule
