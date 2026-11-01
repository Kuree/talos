// CLAUSE: callback preactive
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/4.4.3.2/callback.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;int x=0;import "DPI-C" context function int arm();import "DPI-C" context function int sample();
initial #1 x=1;
initial begin if(!arm())$fatal(1,"callback registration");#2;if(sample()!=0)$fatal(1,"callback sample");$display("PASS");$finish;end endmodule
