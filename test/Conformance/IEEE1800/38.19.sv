// CLAUSE: array handle invalid indices
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.19/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[2]='{4,7};
import "DPI-C" context function int probe();
initial begin if(!probe())$fatal(1,"vpi_handle_by_index");$display("PASS");$finish;end
endmodule
