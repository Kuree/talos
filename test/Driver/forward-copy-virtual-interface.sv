// RUN: talos -O3 --forward-copies=off %s -o %t.base && %t.base > %t.base.out
// RUN: FileCheck %s < %t.base.out
// RUN: talos -O3 %s -o %t.native && %t.native > %t.native.out
// RUN: diff -u %t.base.out %t.native.out
// RUN: talos -O3 --execution-tier=bytecode %s -o %t.bytecode && %t.bytecode > %t.bytecode.out
// RUN: diff -u %t.base.out %t.bytecode.out

// IEEE 1800-2023 25.9: virtual-interface field accesses select the storage
// and nets of the currently bound instance. Such opaque references must
// preserve materialized assignments (10.3.2), including writes through them.
interface forward_copy_channel;
  logic source;
  logic storage_copy;
  wire net_copy = ~source;
  assign storage_copy = ~source;
endinterface

module forward_copy_virtual_interface;
  forward_copy_channel left(), right();
  virtual forward_copy_channel selected;
  initial begin
    left.source = 0;
    right.source = 1;
    selected = left;
    #1;
    $display("left=%b/%b", selected.storage_copy, selected.net_copy);
    selected = right;
    #1;
    $display("right=%b/%b", selected.storage_copy, selected.net_copy);
    selected.source = 0;
    #1;
    $display("right-write=%b/%b", selected.storage_copy, selected.net_copy);
    selected = left;
    selected.source = 1;
    #1;
    $display("left-write=%b/%b", selected.storage_copy, selected.net_copy);
    $display("static=%b/%b:%b/%b", left.storage_copy, left.net_copy,
             right.storage_copy, right.net_copy);
    $finish(0);
  end
endmodule

// CHECK: left=1/1
// CHECK-NEXT: right=0/0
// CHECK-NEXT: right-write=1/1
// CHECK-NEXT: left-write=0/0
// CHECK-NEXT: static=0/0:1/1
