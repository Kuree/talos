// CLAUSE: Return statement: vpiReturnStmt from a function's vpiStmt gives its value through vpiCondition, NULL for a bare return
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.78/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: vpiFunction stmt=vpiReturnStmt condition=vpiAddOp value=10
// CHECK: vpiTask stmt=vpiReturnStmt condition=null
// CHECK: r=10 m=1

module top;
int n = 3, r, m;
function int f();
  return n + 7;
endfunction
task t;
  m = 1;
  return;
  m = 2;
endtask
import "DPI-C" context function void probe();
initial begin
  r = f();
  t();
  probe();
  $display("r=%0d m=%0d", r, m);
  $finish;
end
endmodule
