// CLAUSE: Attribute: vpiAttribute iterates an object's attributes with vpiName, value (1 when none is given), vpiParent and vpiDefAttribute
// XFAIL: *
// vpi_iterate(vpiAttribute, ...) is NULL for every object: attribute instances are not retained in the reflection data.
// RUN: %clang -c -fPIC %S/Inputs/37.83/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: v: vpiAttribute name=mark value=7 parent=v def=0
// CHECK-DAG: w: vpiAttribute name=flag value=1 parent=w def=0
// CHECK-DAG: top: vpiAttribute name=part value=3 parent=top def=1
// CHECK-DAG: statement: vpiAttribute name=note value=4 parent=vpiAssignment def=0

(* part = 3 *)
module top;
(* mark = 7 *) logic v;
(* flag *) logic w;
import "DPI-C" context function void probe();
initial begin
  (* note = 4 *) v = 1;
  probe();
  $finish;
end
endmodule
