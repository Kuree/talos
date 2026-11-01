// CLAUSE: named assertion handle
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/39.3.2/vpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns; timeprecision 1ns;
bit clk=0;check_one:assert property(@(posedge clk)1'b1);import "DPI-C" context function int c39_static_assertion();
initial begin
#1;if(c39_static_assertion()!=1)$fatal(1,"assertion handle");
$display("PASS"); $finish;
end
endmodule
