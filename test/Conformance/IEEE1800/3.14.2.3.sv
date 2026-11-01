// CLAUSE: Time units come from nesting, then `timescale, then the compilation unit; a mix is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/3.14.2.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: design element does not have a time scale defined but others in the design do
// CHECK: nested 100ps{{$}}
// CHECK-NEXT: compilation unit 1000ps{{$}}
// CHECK-NEXT: timescale 10000ps{{$}}

// 3.14.2.3: rules a, b and c each give the same #1 a different length, compared on one picosecond scale.
timeunit 1ns;
timeprecision 1ps;
module cu_mod;
  initial #1 $display("compilation unit %0t", $realtime);
endmodule
`timescale 10ns / 1ns
module ts_mod;
  initial #1 $display("timescale %0t", $realtime);
endmodule
module top;
  timeunit 100ps;
  timeprecision 1ps;
  module nested;
    initial #1 $display("nested %0t", $realtime);
  endmodule
  nested n();
  cu_mod c();
  ts_mod t();
  initial begin
    $timeformat(-12, 0, "ps", 0);
    #200 $finish;
  end
endmodule
