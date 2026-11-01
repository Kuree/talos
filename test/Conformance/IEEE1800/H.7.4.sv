// CLAUSE: scalar mapping
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.7.4/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" function int c35_scalar(input int i,input byte b,input shortint s,input longint l,input real r,input shortreal sr,input bit bv,input logic lv);
initial begin
if(c35_scalar(17,-3,-1200,-10000000000,2.5,shortreal'(1.25),1'b1,1'bz)!=1)$fatal(1,"scalar ABI");
$display("PASS"); $finish;
end
endmodule
