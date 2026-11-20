// RUN: talos -O3 --vpi=off %s -o %t.native
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.native > %t.out
// RUN: FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref
// RUN: %t.ref | diff -u %t.out -

module top;
  logic [3:0] q[$];
  bit initialized;
  int observed;

  initial begin
    wait (initialized);
    wait (q.size() == 2);
    observed++;
    wait (q[0] === 4'hb);
    observed++;
  end

  initial begin
    q.push_back(4'b1zx0);
    initialized = 1;
    #1 q.push_back(q[0]);
    #1 q[0] = 4'hb;
    #1;
    if (observed != 2 || q[1] !== 4'b1zx0)
      $fatal(1, "append/write delivery observed=%0d tail=%b", observed, q[1]);
    $display("append observed=%0d tail=%b", observed, q[1]);
    $finish;
  end
endmodule
// CHECK: append observed=2 tail=1zx0
