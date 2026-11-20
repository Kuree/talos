// RUN: talos -O3 --vpi=off --mlir-timing %s -o %t.native 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t.native > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -

class item;
  logic [3:0] flags = 0;
  byte count = 1, saved;
  function new();
    saved = count;
    count = 2;
    flags = 4'b10x1;
  endfunction
endclass
module top;
  initial begin
    item obj = new;
    $display("flags=%b count=%0d saved=%0d", obj.flags, obj.count, obj.saved);
    $finish;
  end
endmodule
// CHECK: flags=10x1 count=2 saved=1
// PLAN: talos fresh constructor stores: elided=2
