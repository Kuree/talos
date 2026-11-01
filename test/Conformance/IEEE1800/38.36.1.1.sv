// CLAUSE: cbStmt calls back just before a statement executes, with its handle, the time, a NULL value and user_data, once per registration
// XFAIL: *
// vpi_register_cb rejects cbStmt with "reason is not implemented" (docs/vpi.md: cbStmt dispatch is not yet implemented).
// RUN: %clang -c -fPIC %S/Inputs/38.36.1.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: statements=vpiNamedBegin,vpiNamedBegin
// CHECK-NEXT: registered=3
// CHECK-NEXT: twice reason=1 rtn=1 obj=top.first time=1 value=null index=0 x=0
// CHECK-NEXT: twice reason=1 rtn=1 obj=top.first time=1 value=null index=0 x=0
// CHECK-NEXT: suppressed reason=1 rtn=1 obj=top.second time=none value=null index=0 x=1
// CHECK-NEXT: after x=2

module top;
timeunit 1ns; timeprecision 1ns;
int x = 0;
import "DPI-C" context function void setup();
initial begin
  setup();
  #1;
  begin : first
    x = 1;
  end
  begin : second
    x = 2;
  end
  $display("after x=%0d", x);
  $finish;
end
endmodule
