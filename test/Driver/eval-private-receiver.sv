// RUN: talos -O3 --vpi=off --mlir-timing %s -o %t.native 2> %t.plan && FileCheck %s --check-prefix=PLAN < %t.plan
// RUN: %t.native > %t.out && FileCheck %s < %t.out
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.ref && %t.ref | diff -u %t.out -
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.native | diff -u %t.out -
// RUN: talos -O3 --two-state --vpi=off %s -o %t.2s && %t.2s > %t.2s.out
// RUN: talos -O0 --two-state --execution-tier=bytecode %s -o %t.2s.ref && %t.2s.ref | diff -u %t.2s.out -

class packet;
  logic [72:0] value;
  int changes;
  string label_text;
  function new(logic [72:0] seed);
    value = seed;
    label_text = "trace-packet";
  endfunction
  function void replace_low(logic [2:0] bits);
    value[2:0] = bits;
    changes++;
  endfunction
  function string describe(logic [2:0] bits);
    replace_low(bits);
    return $sformatf("%s %b:%b %0d", label_text, value[72:69], value[3:0], changes);
  endfunction
endclass

module top;
  packet published;
  function automatic string temporary(logic [72:0] seed);
    packet local_item = new(seed);
    return local_item.describe(3'bx0z);
  endfunction
  initial begin
    packet alias_item;
    $display("private %s", temporary({4'b1zx0, 65'b0, 4'b1000}));
    published = new({4'bz10x, 65'b0, 4'b0000});
    alias_item = published;
    $display("shared %s", published.describe(3'bz1x));
    $display("alias %b %0d", alias_item.value[2:0], alias_item.changes);
    $finish;
  end
endmodule
// PLAN: talos private class fields: allocations={{[1-9][0-9]*}} methods={{[1-9][0-9]*}} accesses={{[1-9][0-9]*}}
// CHECK: private trace-packet 1zx0:1x0z 1
// CHECK-NEXT: shared trace-packet z10x:0z1x 1
// CHECK-NEXT: alias z1x 1
