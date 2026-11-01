// CLAUSE: timeunit and timeprecision set a scope time scale; a late declaration is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/3.14.2.2/late.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/3.14.2.2/mismatch.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: time scale declaration must come before all other items in scope
// DIAG: duplicate time scale declaration must match previous value
// CHECK: E 0.123{{$}}
// CHECK-NEXT: D 1.50 2{{$}}
// CHECK-NEXT: D 1.60{{$}}

// 3.14.2.2: #1.5 is 150 ps under the unit of 100 ps; #0.123 rounds to 10 ps in D but stays 12.3 ps under E's 10 fs.
module D;
  timeunit 100ps;
  timeprecision 10ps;
  initial begin
    #1.5 $display("D %0.2f %0d", $realtime, $time);
    #0.123 $display("D %0.2f", $realtime);
  end
  timeunit 100ps;            // repeats and matches
endmodule
module E;
  timeunit 100ps / 10fs;
  initial #0.123 $display("E %0.3f", $realtime);
endmodule
module top;
  timeunit 1ns / 1ps;
  D d();
  E e();
  initial #1 $finish;
endmodule
