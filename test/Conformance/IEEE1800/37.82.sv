// CLAUSE: Active time format: vpiActiveTimeFormat is NULL before $timeformat and then the latest $timeformat call, with its arguments
// XFAIL: *
// vpi_handle(vpiActiveTimeFormat, NULL) stays NULL after $timeformat: the active format call is not exposed.
// RUN: %clang -c -fPIC %S/Inputs/37.82/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: before: null
// CHECK: first: vpiSysTaskCall name=$timeformat args=-9,2,8
// CHECK: second: vpiSysTaskCall name=$timeformat args=-3,1,6
// CHECK: formatted: 10.0 ms

module top;
timeunit 1ms; timeprecision 1ms;
import "DPI-C" context function void probe(input string when);
initial begin
  probe("before");
  $timeformat(-9, 2, " ns", 8);
  probe("first");
  #10 $timeformat(-3, 1, " ms", 6);
  probe("second");
  $display("formatted: %t", $time);
  $finish;
end
endmodule
