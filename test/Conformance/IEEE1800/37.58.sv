// CLAUSE: Simple expressions: bit-selects give their name, parent, index and constant-select flag, track their index, and vpiUse lists the uses of a vector and of a bit
// XFAIL: *
// a parameter bit-select reports name=null where the name is P[3]
// RUN: %clang -c -fPIC %S/Inputs/37.58/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: c0 type={{vpiVarBit|vpiRegBit}} name=v[3] full=top.v[3] constant=1 parent=v index=3 value=0
// CHECK: param type=vpiBitSelect name=P[3] full=top.P[3] constant=1 parent=P index=3 value=1
// CHECK: dyn type={{vpiVarBit|vpiRegBit}} constant=0 parent=u index=i index_value=2 value=1
// CHECK: dyn type={{vpiVarBit|vpiRegBit}} constant=0 parent=u index=i index_value=0 value=0
// CHECK-DAG: vector use lhs=c0
// CHECK-DAG: vector use lhs=whole
// CHECK-DAG: vector use lhs=low
// CHECK-DAG: vector use lhs=high
// CHECK: vector uses=4
// CHECK-DAG: bit use lhs=c0
// CHECK-DAG: bit use lhs=whole
// CHECK-DAG: bit use lhs=low
// CHECK: bit uses=3

// Details 1 and 2: v[3] is used by c0, by the whole vector in whole and by the part-select in low, but not by high's v[7:4].
// Detail 3: the select of u changes object as i changes, so it is not a constant select and its value follows i.
module top;
  parameter logic [3:0] P = 4'b1001;
  logic [7:0] v = 8'b1010_0101;
  logic [7:0] u = 8'b0000_0100;
  int i = 2;
  wire c0, dyn, param_bit;
  wire [7:0] whole;
  wire [3:0] low, high;
  assign c0 = v[3];
  assign dyn = u[i];
  assign param_bit = P[3];
  assign whole = v;
  assign low = v[3:0];
  assign high = v[7:4];
  import "DPI-C" context function void describe();
  import "DPI-C" context function void dynamic();
  import "DPI-C" context function void uses();
  initial begin
    #1 describe();
    dynamic();
    i = 0;
    #1 dynamic();
    uses();
    $finish;
  end
endmodule
