// CLAUSE: Repeat control: an intra-assignment repeat gives its count through vpiExpr and its event through vpiEventControl
// XFAIL: *
// vpiExpr is null on vpiRepeatControl: the repeat count is not retained; vpiEventControl works.
// RUN: %clang -c -fPIC %S/Inputs/37.69/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: control=vpiRepeatControl count=2 event=vpiEventControl condition=go n=5 at 2

module top;
timeunit 1ns; timeprecision 1ns;
event go;
int n;
import "DPI-C" context function void probe(input longint now);
always #1 -> go;
initial begin
  n = repeat (2) @go 5;
  probe($time);
  $finish;
end
endmodule
