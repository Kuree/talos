// CLAUSE: named assertion lookup
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/39.3.1/vpi_lookup.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk;check_one:assert property(@(posedge clk)1'b1);import "DPI-C" context function int c37_find(input string name);
initial begin
if(c37_find("top.check_one")!=1)$fatal(1,"named assertion lookup");
$display("PASS"); $finish;
end
endmodule
