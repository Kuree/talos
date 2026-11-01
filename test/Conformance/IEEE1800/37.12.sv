// CLAUSE: Scope: named blocks are scopes reachable through vpiInternalScope, an unnamed begin is one only with a declaration, and vpiJoinType reports a fork's join
// XFAIL: *
// vpiInternalScope of an instance omits named begins, named forks and scope-forming unnamed begins, and vpi_handle_by_name("top.blk") finds nothing; they are reachable only through vpiProcess and vpiStmt.
// RUN: %clang -c -fPIC %S/Inputs/37.12/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK-DAG: scope type=vpiNamedBegin name=blk full=top.blk up=top
// CHECK-DAG: scope type=vpiNamedFork name=f full=top.f up=top join-any=1
// CHECK-DAG: scope type=vpiFunction name=probe full=top.probe up=top
// CHECK-DAG: scope type=vpiBegin vars=1 up=top
// CHECK: unnamed begin scopes=1
// CHECK: nested full=top.blk.inner var=top.blk.inner.v value=3

module top;
import "DPI-C" context function void probe();
int sink;
initial begin : blk
  begin : inner
    static int v = 3;
    sink = v;
  end
end
initial fork : f
  sink = 1;
join_any
// Detail 1: this unnamed begin declares a variable, so it is a scope; the one around it is not.
initial begin
  begin
    static int local_var = 1;
    sink += local_var;
  end
end
initial begin #1 probe(); $finish; end
endmodule
