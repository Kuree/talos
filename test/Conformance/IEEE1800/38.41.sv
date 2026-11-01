// CLAUSE: vpi_vprintf writes from an already started va_list, continuing where it stands, and returns the character count
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.41/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: before
// CHECK-NEXT: a=12 b=xy
// CHECK-NEXT: v=222
// CHECK-NEXT: after count=16

module top;
import "DPI-C" context function int probe();
int count;
initial begin
  $display("before");
  count = probe();
  $display("after count=%0d", count);
  $finish;
end
endmodule
