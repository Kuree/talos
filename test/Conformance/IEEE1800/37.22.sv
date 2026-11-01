// CLAUSE: Object range: vpiRange gives a variable's declared bounds as expressions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.22/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: type=vpiRange left=7 right=4
// CHECK: outer=[3:0] inner=[1:2] more=0

module top;
logic [7:4] v;
logic [3:0] [1:2] w;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
