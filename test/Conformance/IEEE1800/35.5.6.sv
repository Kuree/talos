// CLAUSE: scalar mapping
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.5.6/dpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
import "DPI-C" function void c35_wide(output bit [64:0] v);bit[64:0]v;
initial begin
c35_wide(v);if(v!==65'h1_12345678_89abcdef)$fatal(1,"wide ABI=%h",v);
$display("PASS"); $finish;
end
endmodule
