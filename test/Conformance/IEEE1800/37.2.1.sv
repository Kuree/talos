// CLAUSE: Handle creation
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.2.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int n=7;import "DPI-C" context function int probe();
initial begin
if(!probe())$fatal(1,"VPI contract");
$display("PASS");$finish;
end
endmodule
