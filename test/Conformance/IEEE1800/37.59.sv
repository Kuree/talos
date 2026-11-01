// CLAUSE: Expressions: operations give their type, ordered operands, size, live value and decompilation; constants, part-selects and indexed part-selects give their own properties
// XFAIL: *
// expression text is printed as 'a+ b' and constant string and real flags are 0
// RUN: %clang -c -fPIC %S/Inputs/37.59/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: sum type=vpiOperation add=1 size=8 text=a + b value=7
// CHECK-NEXT: operand {{vpiLogicVar|vpiReg}} value=3
// CHECK-NEXT: operand {{vpiLogicVar|vpiReg}} value=4
// CHECK: product mult=1 text=(a + b) * c value=14
// CHECK: rep multi_concat=1
// CHECK-NEXT: operand vpiConstant value=2
// CHECK-NEXT: operand vpiPartSelect value=3
// CHECK-NEXT: operand vpiConstant value=1
// CHECK: const integer=1 string=1 real=1
// CHECK: part type=vpiPartSelect constant=1 parent=a left=1 right=0 value=3
// CHECK: indexed type=vpiIndexedPartSelect constant=0 positive=1 parent=a base=idx width=2 value=1
// CHECK: cast is_cast=1 typespec=vpiByteTypespec operand=a value=3
// CHECK: after sum=9 product=18 part=1 indexed=2

// Detail 1: the replication's first operand is its multiplier. Detail 2: parentheses only where needed, single spaces.
// Detail 3: a cast is a unary operation with a typespec. Detail 9: idx is not a constant, so a[idx +: 2] is not a constant select.
module top;
  logic [7:0] a = 3, b = 4, c = 2;
  logic [15:0] text = "hi";
  real r = 2.5;
  int idx = 1;
  wire [7:0] sum, product, casted;
  wire [7:0] rep;
  wire [1:0] part, indexed;
  wire is_hi, is_big;
  assign sum = a + b;
  assign product = (a + b) * c;
  assign rep = {2{a[1:0], 2'b01}};
  assign is_hi = text == "hi";
  assign is_big = r > 1.5;
  assign part = a[1:0];
  assign indexed = a[idx +: 2];
  assign casted = byte'(a);
  import "DPI-C" context function void describe();
  import "DPI-C" context function void after();
  initial begin
    #1 describe();
    a = 5;
    #1 after();
    $finish;
  end
endmodule
