// CLAUSE: Clocking block input, output, inout and expression clockvars; writing an input is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/14.3/write_input.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/14.3/read_output.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot write to input clocking signal 'value'
// DIAG: cannot read from output clocking signal 'value'
// CHECK: 5 in=02 raw=03 pin=aa hold=40{{$}}
// CHECK-NEXT: 5 out=00 pin=aa{{$}}
// CHECK-NEXT: 7 out=55 pin=5a{{$}}
// CHECK-NEXT: 15 in=03 pin=5a hold=41{{$}}

// 14.3: an input reads its value at the skew before the clock, an output drives after it, an inout does both.
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk = 0;
  always #5 clk = ~clk;
  logic [7:0] in = 8'h01, out = 0, pin = 8'haa, src = 8'h40;
  clocking cb @(posedge clk);
    input #2 in;
    output #1 out;
    inout pin;
    input hold = src;
  endclocking
  initial begin
    #2 in = 8'h02;           // before the sample point at 5-2
    #2 in = 8'h03;           // after it
    @(cb);                   // t=5
    $display("%0t in=%h raw=%h pin=%h hold=%h", $time, cb.in, in, cb.pin, cb.hold);
    cb.out <= 8'h55;
    cb.pin <= 8'h5a;
    src = 8'h41;
    $display("%0t out=%h pin=%h", $time, out, pin);
    #2 $display("%0t out=%h pin=%h", $time, out, pin);
    @(cb);                   // t=15
    $display("%0t in=%h pin=%h hold=%h", $time, cb.in, cb.pin, cb.hold);
    $finish;
  end
endmodule
