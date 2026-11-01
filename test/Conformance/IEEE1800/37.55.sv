// CLAUSE: Immediate assertions: assert, assume and cover statements give their type, deferred and final flags, condition with its value, and action statements
// XFAIL: *
// immediate assertions are reported as vpiNamedBegin, not vpiImmediateAssert
// RUN: %clang -c -fPIC %S/Inputs/37.55/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: assert passed
// CHECK: assume failed
// CHECK: covered
// CHECK: ia type=vpiImmediateAssert deferred=0 final=0 expr=a == 1 value=1 stmt=vpiSysTaskCall else=vpiSysTaskCall
// CHECK: iu type=vpiImmediateAssume deferred=0 final=0 expr=a == 0 value=0 stmt=null else=vpiSysTaskCall
// CHECK: ic type=vpiImmediateCover deferred=0 final=0 expr=a value=1 stmt=vpiSysTaskCall else=null
// CHECK: d0 type=vpiImmediateAssert deferred=1 final=0 expr=a value=1 stmt=null else=null
// CHECK: df type=vpiImmediateAssert deferred=1 final=1 expr=a value=1 stmt=null else=null

// 16.4: assert #0 is an observed deferred assertion and assert final a final deferred assertion.
module top;
  logic a = 1;
  import "DPI-C" context function void probe();
  initial begin
    ia: assert (a == 1) $display("assert passed"); else $display("assert failed");
    iu: assume (a == 0) else $display("assume failed");
    ic: cover (a) $display("covered");
    d0: assert #0 (a);
    df: assert final (a);
    probe();
    $finish;
  end
endmodule
