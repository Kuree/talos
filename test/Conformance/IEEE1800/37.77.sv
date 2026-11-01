// CLAUSE: Disables: vpiDisable names its task or named block through vpiExpr, disable fork is vpiDisableFork, and each stopped its target
// XFAIL: *
// vpiExpr is null on vpiDisable: the disabled task or block is not retained; the statement kinds and their execution work.
// RUN: %clang -c -fPIC %S/Inputs/37.77/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// A block's statements come in no promised order, so they match in any order.
// CHECK-DAG: vpiDisable target=vpiNamedBegin:blk
// CHECK-DAG: vpiDisable target=vpiTask:t
// CHECK-DAG: vpiDisableFork target=none
// CHECK: stopped n=0 m=0 k=0

module top;
int n, m, k;
task t;
  #5 m = 1;
endtask
import "DPI-C" context function void probe();
initial begin
  fork begin : blk #5 n = 1; end join_none
  fork t(); join_none
  #1;
  disable blk;
  disable t;
  fork #5 k = 1; join_none
  #1;
  disable fork;
  #10 probe();
  $display("stopped n=%0d m=%0d k=%0d", n, m, k);
  $finish;
end
endmodule
