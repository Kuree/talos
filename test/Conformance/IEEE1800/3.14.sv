// CLAUSE: Delays scale with time units of magnitude 1, 10 and 100; other magnitudes are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/3.14/magnitude.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/3.14/precision.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: time scale must have a value of 1, 10, or 100
// DIAG: time precision must be at least as precise as the time unit
// CHECK: rounded 1300ps{{$}}
// CHECK-NEXT: 1ns 1500ps{{$}}
// CHECK-NEXT: 10ns 15000ps{{$}}
// CHECK-NEXT: 100ns 150000ps{{$}}

// 3.14: the same #1.5 lands at a time set by each unit, and the precision rounds #1.26.
module m1;
  timeunit 1ns; timeprecision 1ps;
  initial #1.5 $display("1ns %0t", $realtime);
endmodule
module m10;
  timeunit 10ns; timeprecision 1ps;
  initial #1.5 $display("10ns %0t", $realtime);
endmodule
module m100;
  timeunit 100ns; timeprecision 1ps;
  initial #1.5 $display("100ns %0t", $realtime);
endmodule
module rounded;
  timeunit 1ns; timeprecision 100ps;
  initial #1.26 $display("rounded %0t", $realtime);
endmodule
module top;
  timeunit 1ns; timeprecision 1ps;
  m1 a();
  m10 b();
  m100 c();
  rounded d();
  initial begin
    $timeformat(-12, 0, "ps", 0);
    #200 $finish;
  end
endmodule
