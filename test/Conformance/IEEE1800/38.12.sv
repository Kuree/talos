// CLAUSE: vpi_get_systf_info returns what vpi_register_systf was given, for a task and a sized function
// SINCE: 0.1.0
// RUN: %clang -shared -fPIC %S/Inputs/38.12/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: $probe_task task=1 functype=0 calltf=1 compiletf=1 sizetf=1 user=task data
// CHECK-NEXT: $probe_func func=1 functype=sized calltf=1 compiletf=1 sizetf=1 user=func data

module top;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
