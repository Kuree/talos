// CLAUSE: vpi coverage control
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/40.5.3/vpi_coverage_min.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full --coverage=toggle -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit q;import "DPI-C" context function int c40_control();
initial begin
#1;if(c40_control()!=1)$fatal(1,"VPI coverage stop");
$display("PASS"); $finish;
end
endmodule
