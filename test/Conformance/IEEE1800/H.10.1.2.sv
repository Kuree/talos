// CLAUSE: Normalized and linearized ranges
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.10.1.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
import "DPI-C" function int f(input bit[6:9] x);
initial begin
if(f(4'b1010)!=10)$fatal(1,"canonical range");
$display("PASS");$finish;
end
endmodule
