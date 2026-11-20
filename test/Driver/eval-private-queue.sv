// RUN: talos -O3 --vpi=off --mlir-timing %s -o %t.native 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t.native > %t.out && FileCheck %s < %t.out
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.native | diff -u %t.out -
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off %s -o %t.two && %t.two > %t.two.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.ref2 && %t.ref2 | diff -u %t.two.out -

class packet;
  logic [4:0] fields[$];
  function void push(logic [4:0] v);
    fields.push_back(v);
  endfunction
  function string run(logic [4:0] v);
    logic [4:0] first;
    push(5'h1a);
    push(v);
    first = fields.pop_front();
    // The first four slots fit inline. Growth copies a wrapped ring.
    for (int i = 0; i < 8; i++)
      push(5'(i));
    return $sformatf("%h %b %0d %0d %b", first, fields[0], fields.size(),
                     fields[8], fields[-1]);
  endfunction
endclass

module top;
  function automatic string trace(logic [4:0] v);
    packet item = new;
    return item.run(v);
  endfunction
  initial $display("%s", trace(5'b1zx01));
endmodule
// PLAN: talos private queues: accesses={{[1-9][0-9]*}}
// CHECK: 1a 1zx01 9 7 xxxxx
