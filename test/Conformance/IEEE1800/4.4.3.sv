// CLAUSE: callback preactive
// XFAIL: *
// cbAtEndOfSimTime callback registration is not implemented by this runtime.
// RUN: %clang -c -fPIC %S/Inputs/4.4.3/callback.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;int x=0;import "DPI-C" context function int arm();import "DPI-C" context function int sample();
initial begin #1;x<=1;if(!arm())$fatal(1,"callback registration");#1;if(sample()!=1)$fatal(1,"callback sample");$display("PASS");$finish;end endmodule
