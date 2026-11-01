// CLAUSE: Atomic statement: a block's statements report their vpiType, vpiNullStmt for a semicolon, and vpiName as the label or NULL
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.60/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Block iteration order is not promised, so the block's statements match in any order.
// A label on a plain statement makes a named block around it; on a foreach it names the loop (9.3.5).
// CHECK-DAG: vpiNullStmt label=null
// CHECK-DAG: vpiNamedBegin label=first body=vpiAssignment
// CHECK-DAG: vpiForeachStmt label=walk
// CHECK-DAG: vpiAssignment label=null
// CHECK-DAG: vpiImmediateAssert label=null
// CHECK-DAG: vpiImmediateAssume label=null
// CHECK-DAG: vpiImmediateCover label=null
// CHECK-DAG: vpiForever label=null body=vpiBreak
// CHECK-DAG: vpiRepeat label=null body=vpiContinue
// CHECK: labels=2 statements=11

module top;
int n, m, q[2];
import "DPI-C" context function void probe();
initial begin
  ;
  first: n = 5;
  walk: foreach (q[i]) q[i] = i;
  m = n + 1;
  assert (m == 6);
  assume (m == 6);
  cover (m == 6);
  forever break;
  repeat (1) continue;
  probe();
  $finish;
end
endmodule
