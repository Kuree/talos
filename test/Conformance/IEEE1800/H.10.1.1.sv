// CLAUSE: four state scalar
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.10.1.1/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" function logic c35_logic(input logic a);
initial begin
if(c35_logic(1'bx)!==1'bx || c35_logic(1'bz)!==1'bz)$fatal(1,"logic ABI");
$display("PASS"); $finish;
end
endmodule
