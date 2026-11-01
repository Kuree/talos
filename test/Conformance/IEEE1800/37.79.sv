// CLAUSE: Assign, deassign, force, release: each statement's vpiType with vpiLhs, vpiRhs for assign and force, and each took effect
// XFAIL: *
// vpiLhs and vpiRhs are null on vpiAssignStmt, vpiDeassign, vpiForce and vpiRelease; the statement kinds and their execution work.
// RUN: %clang -c -fPIC %S/Inputs/37.79/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: assigned v=1
// CHECK: followed v=0
// CHECK: deassigned v=0
// CHECK: forced w=1
// CHECK: released w=0
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiAssignStmt lhs=v rhs=src
// CHECK-DAG: vpiDeassign lhs=v rhs=none
// CHECK-DAG: vpiForce lhs=w rhs=src
// CHECK-DAG: vpiRelease lhs=w rhs=none

module top;
logic v, src;
wire w;
assign w = 0;
import "DPI-C" context function void probe();
initial begin
  src = 1;
  assign v = src;
  #1 $display("assigned v=%b", v);
  src = 0;
  #1 $display("followed v=%b", v);
  deassign v;
  src = 1;
  #1 $display("deassigned v=%b", v);
  force w = src;
  #1 $display("forced w=%b", w);
  release w;
  #1 $display("released w=%b", w);
  probe();
  $finish;
end
endmodule
