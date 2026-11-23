// RUN: %target_clang %target_pic -c %S/Inputs/vpi-element-writes.c \
// RUN:   -I%resource_dir/include -o %t.o
// RUN: talos --std=1800-2023 --top=top --vpi=full -O3 %s %t.o -o %t.exe
// RUN: %t.exe | FileCheck %s --match-full-lines

// IEEE 1800-2023 38.34: vpi_put_value writes a selected array element, memory
// word, vector bit or structure member and leaves the rest of the variable
// unchanged, including an element that straddles a 64-bit word. A process
// waiting on the written element wakes; one waiting on another element does
// not. A 2-state target, even inside a 4-state variable, stores x and z as 0
// (6.11.2). Writes Talos does not support yet (a tagged union member, which
// would bypass its tag (7.3.2), forcing a selection, a selection of a class
// member, and a string, whose storage is a managed reference) give a notice.
module top;
  typedef struct packed { logic [3:0] hi, lo; } packed_t;
  typedef struct { int a; byte b; } unpacked_t;
  typedef union tagged { int word; void none; } tagged_t;
  class C;
    int items [2];
  endclass
  int ints [3] = '{1, 2, 3};
  logic [3:0] mem [3:1];
  logic [7:0] vec = 8'h00;
  logic [3:0] grid [2][2];
  packed_t packed_s = '{4'h1, 4'h2};
  unpacked_t unpacked_s = '{5, 6};
  tagged_t tagged_u = tagged none;
  C obj = new;
  logic [39:0] wide [3];
  struct { int a; logic [3:0] b; } mixed = '{4, 4'b0101};
  struct packed { bit [3:0] a; logic [3:0] b; } mixed_p = 8'hff;
  int whole_int;
  string names [2] = '{"ab", "cd"};
  string name = "ef";
  import "DPI-C" context function void write_elements();
  always @(ints[1]) $display("woke on ints[1]=%0d", ints[1]);
  always @(ints[0]) $display("woke on ints[0]");
  initial begin
    #1 write_elements();
    #1 $display("ints=%0d,%0d,%0d mem[3]=%b mem[2]=%b vec=%h grid[1][0]=%b grid[0][0]=%b",
                ints[0], ints[1], ints[2], mem[3], mem[2], vec, grid[1][0],
                grid[0][0]);
    $display("packed_s=%h unpacked_s=%0d,%0d obj.items[0]=%0d", packed_s,
             unpacked_s.a, unpacked_s.b, obj.items[0]);
    if (tagged_u matches tagged none)
      $display("tagged_u is still none");
    $display("wide=%h,%h,%h mixed=%0d,%b mixed_p=%b whole_int=%0d", wide[0],
             wide[1], wide[2], mixed.a, mixed.b, mixed_p, whole_int);
    $display("names=%s,%s name=%s", names[0], names[1], name);
  end
endmodule

// CHECK: top.ints[1]=101010: written
// CHECK-NEXT: top.mem[3]=1x0z: written
// CHECK-NEXT: top.vec[2]=1: written
// CHECK-NEXT: top.grid[1][0]=0110: written
// CHECK-NEXT: top.packed_s.hi=1111: written
// CHECK-NEXT: top.unpacked_s.a=111: written
// CHECK-NEXT: top.tagged_u.word=1: writes to a tagged union member are not supported
// CHECK-NEXT: top.ints[2]=1: force and release of a selected element are not supported
// CHECK-NEXT: top.obj.items[0]=1: writes to a selection of a class member are not supported
// CHECK-NEXT: top.wide[1]=1000000000000000000000000000000000000001: written
// CHECK-NEXT: top.mixed.a=zx1: written
// CHECK-NEXT: top.mixed_p.a=x1z0: written
// CHECK-NEXT: top.whole_int=1z: written
// CHECK-NEXT: top.names[0]=1: writes to string variables are not supported
// CHECK-NEXT: top.name=1: writes to string variables are not supported
// CHECK-NEXT: woke on ints[1]=42
// CHECK-NEXT: ints=1,42,3 mem[3]=1x0z mem[2]=xxxx vec=04 grid[1][0]=0110 grid[0][0]=xxxx
// CHECK-NEXT: packed_s=f2 unpacked_s=7,6 obj.items[0]=0
// CHECK-NEXT: tagged_u is still none
// CHECK-NEXT: wide=xxxxxxxxxx,8000000001,xxxxxxxxxx mixed=1,0101 mixed_p=01001111 whole_int=2
// CHECK-NEXT: names=ab,cd name=ef
