// CLAUSE: vpi_get_delays reads the delays of a primitive and a net, in the format time_type selects
// XFAIL: *
// vpi_get_delays reads only net and intermodule-path delays; on a primitive it leaves da untouched and reports "VPI delay metadata is unavailable".
// RUN: %clang -c -fPIC %S/Inputs/38.10/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: gate type=vpiGate
// CHECK-NEXT: gate sim 1000 2000 3000
// CHECK-NEXT: gate scaled 1.00 2.00 3.00
// CHECK-NEXT: net sim 4000 5000 6000

module top;
timeunit 1ns; timeprecision 1ps;
logic a = 0, en = 1;
wire o;
wire #(4, 5, 6) n;
assign n = a;
bufif1 #(1, 2, 3) g(o, a, en);
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
