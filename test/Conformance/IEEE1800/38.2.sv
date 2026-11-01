// CLAUSE: vpi_chk_error returns the failed call's severity and details, keeps them across checks, and a later VPI call clears them
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: failed: handle=null level=vpiError
// CHECK-NEXT: info: level=vpiError state=1 message=1
// CHECK-NEXT: still: level=vpiError
// CHECK-NEXT: clean: n=7 level=0

module top;
int n = 7;
import "DPI-C" context function void probe();
initial begin probe(); $finish; end
endmodule
