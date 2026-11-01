// CLAUSE: Threads: a suspended fork branch's thread is inactive and gives its origin and its running parent, the parent lists its live children, and threads end with their process
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.44/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: waiter type=vpiThread active=0 origin=vpiBegin parent=vpiThread parent_active=1
// CHECK: waiter type=vpiThread active=0 origin=vpiBegin parent=vpiThread parent_active=1
// CHECK: distinct=1 same_parent=1
// CHECK: phase=1 waiters=2 children=2 root_parent=null
// CHECK: phase=2 waiters=0 children=0 root_parent=null

// At phase 1 the branches are suspended on e while the initial thread runs the DPI call; ->e then ends both branches.
module top;
  event e;
  import "DPI-C" context function void probe(int phase);
  initial begin
    fork
      begin @e; end
      begin @e; end
    join_none
    #1 probe(1);
    ->e;
    #1 probe(2);
    $finish;
  end
endmodule
