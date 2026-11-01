// CLAUSE: delay_mode_path module default mode
// XFAIL: *
// The optional directive does not produce the required observed default/range behavior.
// RUN: %clang -c -fPIC %S/Inputs/E.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`delay_mode_path
module top;import "DPI-C" context function int probe();initial begin if(!probe())$fatal(1,"module delay mode");$display("PASS");$finish;end endmodule
