// CLAUSE: rounding and scope
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module fine;
  timeunit 1ns;timeprecision 100ps;
  initial begin #0.14;if($realtime!=0.1)$fatal(1,"fine rounding");end
endmodule
module coarse;
  timeunit 10ns;timeprecision 1ns;
  initial begin #0.14;if($realtime!=0.1)$fatal(1,"coarse rounding");end
endmodule
module top;
  timeunit 1ns;timeprecision 10ps;
  fine a();coarse b();
  initial begin #2;$display("PASS");$finish;end
endmodule
