// CLAUSE: Packed union members overlay the same bits; unequal hard packed widths are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.3.1/width.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.3.1/real.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: all members of a packed union must have the same width; 'narrow' has width of 8, previously seen width was 16
// DIAG: packed members must be of integral type (not 'real')
// CHECK: 12 34 12 34{{$}}
// CHECK-NEXT: 12ff f{{$}}
// CHECK-NEXT: vector 00001300{{$}}
// CHECK-NEXT: 1000 1x0z{{$}}
// CHECK-NEXT: 0101{{$}}
// CHECK-NEXT: soft 10 a5{{$}}

// 7.3.1: writing one member reads back through the others, and soft packed members are right-justified.
module top;
  typedef union packed {
    logic [15:0] word;
    logic [1:0][7:0] bytes;
    struct packed {logic [7:0] hi, lo;} s;
  } U;
  U u;
  union packed {bit [3:0] b; logic [3:0] l;} m;
  union soft packed {bit [9:0] F1; bit [7:0] F2;} sp;
  initial begin
    u.word = 16'h1234;
    $display("%h %h %h %h", u.bytes[1], u.bytes[0], u.s.hi, u.s.lo);
    u.s.lo = 8'hff;
    $display("%h %h", u.word, u[3:0]);
    $display("vector %h", u + 1);
    m.l = 4'b1x0z;
    $display("%b %b", m.b, m.l);
    m.b = 4'b0101;
    $display("%b", m.l);
    sp.F1 = 10'h2a5;
    $display("soft %0d %h", $bits(sp), sp.F2);
    $finish;
  end
endmodule
