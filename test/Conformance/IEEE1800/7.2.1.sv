// CLAUSE: Packed structures lay out members from the MSB and act as one vector; signing an unpacked struct is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.2.1/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: unpacked type cannot have signedness declared
// CHECK: 11223344 5566 77 88{{$}}
// CHECK-NEXT: select 77 64{{$}}
// CHECK-NEXT: vector 11223344ffff7788{{$}}
// CHECK-NEXT: signed 0 unsigned 256{{$}}
// CHECK-NEXT: four state xx a=0 b=x{{$}}

// 7.2.1: the first member is most significant, signedness applies to the whole value, and a 2-state member of a
// 4-state struct converts when read.
module top;
  struct packed signed {
    int a;
    shortint b;
    byte c;
    bit [7:0] d;
  } pack1;
  typedef struct packed {
    bit [3:0] hi;
    bit [3:0] lo;
  } nib_t;
  struct packed signed {
    bit [3:0] hi;
    bit [3:0] lo;
  } sn = 8'hff;
  nib_t un = 8'hff;
  struct packed {
    bit a;
    logic b;
  } m;
  initial begin
    pack1 = 64'h11223344_5566_77_88;
    $display("%h %h %h %h", pack1.a, pack1.b, pack1.c, pack1.d);
    $display("select %h %0d", pack1[15:8], $bits(pack1));
    pack1.b = 16'hffff;
    $display("vector %h", pack1);
    $display("signed %0d unsigned %0d", sn + 1, un + 1);
    m = 2'bxx;
    $display("four state %b a=%b b=%b", m, m.a, m.b);
    $finish;
  end
endmodule
