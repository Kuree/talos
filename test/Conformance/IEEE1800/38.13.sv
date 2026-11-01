// CLAUSE: vpi_get_time gives simulation time in the simulation unit for NULL and a time queue, and scaled time in an object's own timescale
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.13/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: sim high=0 low=5000
// CHECK-NEXT: null scaled=5000.00
// CHECK-NEXT: top scaled=5.00
// CHECK-NEXT: u scaled=0.50
// CHECK-NEXT: next queue high=0 low=7000
// CHECK-NEXT: sim high=1 low=5000

module sub;
timeunit 10ns; timeprecision 1ps;
endmodule
module top;
timeunit 1ns; timeprecision 1ps;
sub u();
import "DPI-C" context function void probe();
import "DPI-C" context function void probe_wide();
initial #7; // an event in the time queue at the first probe
initial begin
  #5 probe();
  #4294967296ps probe_wide(); // 2**32 ps later the time needs its high word
  $finish;
end
endmodule
