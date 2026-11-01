// CLAUSE: Tasks and functions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/35.5.1.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
export "DPI-C" task wait_sv;
task automatic wait_sv(input int x,output int y);#x;y=x;endtask
import "DPI-C" context task call_c(input int x,output int y);int a,b;
initial begin fork call_c(1,a);call_c(2,b);join
if(a!=1 || b!=2 || $time!=2)$fatal(1,"reentrant task");$display("PASS");$finish;end
endmodule
