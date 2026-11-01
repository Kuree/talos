// CLAUSE: An expression traverses as vpiOperation handles whose operands are its subexpressions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/36.10.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: operation mult=1 add=0 value=20
// CHECK:   operation mult=0 add=1 value=5
// CHECK:     leaf a value=2
// CHECK:     leaf b value=3
// CHECK:   leaf c value=4
// CHECK: traversed
// 36.10.3: this is the standard's traverseExpr, printing what it visits.

module top;
  int a = 2, b = 3, c = 4;
  wire [31:0] w;
  assign w = (a + b) * c;
  import "DPI-C" context function void probe();
  initial begin
    #1 probe();
    $finish;
  end
endmodule
