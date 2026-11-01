// CLAUSE: vpi_get_value_array reads contiguous elements from a start index, VPI or user allocated, in the declared order with X bits
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/38.16/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: vpi allocated: 20 30
// CHECK-NEXT: user allocated: 30 40 pointer_kept=1
// CHECK-NEXT: raw: 145/000 156/000 203/000 f04/f00 fff/fff
// CHECK-NEXT: vector: 145/000 156/000
// CHECK-NEXT: inconsistent format: pointer=null error=1

module top;
int a[4] = '{10, 20, 30, 40};
logic [11:0] m[2:0][3:5];
import "DPI-C" context function void probe();
initial begin
  m[1][4] = 12'h145; m[1][5] = 12'h156; m[0][3] = 12'h203; m[0][4] = 12'hx04;
  #1 probe();
  $finish;
end
endmodule
