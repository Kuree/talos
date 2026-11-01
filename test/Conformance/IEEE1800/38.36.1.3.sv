// CLAUSE: cbStmt on a module instance fires for every statement in that instance only, and removing its one handle removes them all
// XFAIL: *
// vpi_register_cb rejects cbStmt with "reason is not implemented" (docs/vpi.md: cbStmt dispatch is not yet implemented).
// RUN: %clang -c -fPIC %S/Inputs/38.36.1.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: handle=vpiCallback
// CHECK-NEXT: vpiBegin scope=top.u.run x=0
// CHECK-NEXT: vpiAssignment scope=top.u.run x=0
// CHECK-NEXT: vpiAssignment scope=top.u.run x=1
// CHECK-NEXT: removed=1
// CHECK-NEXT: firings=3 x=2 other=2

module sub;
int x = 0;
task run;
  begin
    x = 1;
    x = 2;
  end
endtask
endmodule
module top;
sub u();
sub other();
int y;
import "DPI-C" context function void setup();
import "DPI-C" context function void drop();
import "DPI-C" context function int firings();
initial begin
  setup();
  y = 5;       // in top, and
  other.run(); // in another instance of the same module: no callbacks
  u.run();
  drop();
  u.run();     // no callbacks
  $display("firings=%0d x=%0d other=%0d", firings(), u.x, other.x);
  $finish;
end
endmodule
