// CLAUSE: vpi_get64 reads the 64-bit vpiObjId of a class variable and returns vpiUndefined for an object without it
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.7/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: null=0 live=1 alias_same=1 other_differs=1
// CHECK-NEXT: retargeted=1 object_same=1
// CHECK-NEXT: not_a_class=-1 error=1

class C; endclass
module top;
C a, b, c, none;
int n;
import "DPI-C" context function void first();
import "DPI-C" context function void second();
initial begin
  a = new; b = a; c = new;
  first();
  a = c;
  second();
  $finish;
end
endmodule
