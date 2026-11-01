// CLAUSE: Forever: vpiForever gives its repeated body through vpiStmt, and the loop ran
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.70/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: vpiForever body=vpiDelayControl inner=vpiAssignment lhs=n=2

module top;
int n;
import "DPI-C" context function void probe();
initial forever #2 n = n + 1;
initial begin
  #5 probe();
  $finish;
end
endmodule
