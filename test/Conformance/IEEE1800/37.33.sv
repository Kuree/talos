// CLAUSE: Class variables and objects: vpiObjId and vpiClassObj follow what a class var references, and var and object report declared versus allocated class
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.33/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: null var id=0 obj=null
// CHECK: obj type=vpiClassObj
// CHECK: nonzero=1 alias=1 distinct=1 obj_id_matches=1
// CHECK: compare same=1 other=0
// CHECK: declared=Packet
// CHECK: allocated=LinkedPacket
// CHECK: p.Id=42
// CHECK: other.Id=7
// CHECK: null var id=0 obj=null

// The class is the LinkedPacket example of 37.33 detail 5; top.p.Id is the name of detail 9.
module top;
  class Packet;
    integer Id;
  endclass
  class LinkedPacket extends Packet;
  endclass
  LinkedPacket l;
  Packet p;
  Packet other;
  import "DPI-C" context function void probe_null();
  import "DPI-C" context function void probe_live();
  initial begin
    probe_null();
    l = new;
    l.Id = 42;
    p = l;
    other = new;
    other.Id = 7;
    probe_live();
    p = null;
    probe_null();
    $finish;
  end
endmodule
