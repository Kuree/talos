// CLAUSE: Synchronous drives update after the clocking event and output skew; blocking writes are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/14.16/blocking.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/14.16/delay.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: clocking signal 'data' can only be written via a synchronous drive
// DIAG: clocking signals cannot be driven with a timing control other than a cycle delay
// CHECK: 7 data=12{{$}}
// CHECK-NEXT: 17 data=15{{$}}
// CHECK-NEXT: 37 data=56{{$}}
// CHECK-NEXT: 47 data=34{{$}}

// 14.16: each drive prints when it lands, so a late, early or re-evaluated drive shows up in the order and times.
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk = 0;
  always #5 clk = ~clk;
  logic [7:0] data = 0, r = 8'h34;
  default clocking cb @(posedge clk);
    output #2 data;
  endclocking
  always @(data) $display("%0t data=%h", $time, data);
  initial begin
    @(cb);                   // t=5
    cb.data <= 8'h12;        // driven at 5+2
    ##1;                     // t=15
    cb.data[3:0] <= 4'h5;    // driven at 15+2
    ##1;                     // t=25
    cb.data <= ##2 r;        // value taken now, driven at 45+2
    r = 8'h56;
    #3;                      // t=28, between clocking events
    cb.data <= r;            // value taken now, driven at 35+2
    r = 8'h78;
    #22 $finish;
  end
endmodule
