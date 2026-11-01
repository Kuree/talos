// CLAUSE: Callback removal
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.39/vpi.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
timeunit 1ns;timeprecision 1ns;
import "DPI-C" context function int register_and_remove();
import "DPI-C" context function int callback_count();
initial begin
if(!register_and_remove())$fatal(1,"removal");
#3;if(callback_count()!=0)$fatal(1,"removed callback fired");
$display("PASS");$finish;
end
endmodule
