// CLAUSE: Allocating actual arguments for SystemVerilog-specific types
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.8.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
export "DPI-C" function take;function int take(input logic[3:0]v);return v;endfunction
import "DPI-C" context function int f();
initial begin
if(f()!=5)$fatal(1,"C allocated vector actual");
$display("PASS");$finish;
end
endmodule
