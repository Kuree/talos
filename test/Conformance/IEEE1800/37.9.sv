// CLAUSE: Program: a program instance reports its type, definition, processes, default clocking and vpiIndex only inside an instance array
// XFAIL: *
// vpiDefaultClocking of a program reports clocking=null
// RUN: %clang -c -fPIC %S/Inputs/37.9/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: program type=vpiProgram name=p def=prog full=top.p index=null processes=2 clocking=cb
// CHECK: element full=top.pa[1] index=1
// CHECK: value v=4

program prog(input logic clk);
int v = 3;
default clocking cb @(posedge clk); endclocking
initial v = 4;
initial #2;
endprogram
module top;
logic clk = 0;
prog p(clk);
prog pa[2:1](clk);
import "DPI-C" context function void probe();
initial begin #1 probe(); $finish; end
endmodule
