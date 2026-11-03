// RUN: talos -O3 %s -o %t
// RUN: %t | FileCheck %s

// Stores that nothing consumes skip publication and only update the value
// (IEEE 1800-2023 4.3; two-tier B2 Q4). Consumers that arrive later must still
// see every change: a $monitor started mid-run (21.2.3) and event controls
// that begin waiting after many unconsumed changes (9.4.2), for a blocking
// store and a nonblocking one.

module native_unconsumed_store_late_consumers;
  logic clk = 0;
  logic [7 : 0] r = 0;
  logic [7 : 0] s = 0;
  always
    #5 clk = ~clk;
  always @(posedge clk) begin
    r = r + 1;
    s <= s + 2;
  end
  initial begin
    #42;
    @(r) $display("%0t r changed to %0d",
                  $time,
                  r);
    @(s) $display("%0t s changed to %0d",
                  $time,
                  s);
    #20 $finish;
  end
  initial begin
    #23 $monitor("%0t monitor r=%0d s=%0d", $time, r, s);
  end
endmodule

// CHECK: 23 monitor r=2 s=4
// CHECK-NEXT: 25 monitor r=3 s=6
// CHECK-NEXT: 35 monitor r=4 s=8
// CHECK-NEXT: 45 r changed to 5
// CHECK-NEXT: 45 s changed to 10
// CHECK-NEXT: 45 monitor r=5 s=10
// CHECK-NEXT: 55 monitor r=6 s=12
