// CLAUSE: Integer literals size, pad, sign and truncate as specified; a digit outside the base is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.7.1/digit.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/5.7.1/sign.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: expected binary digit
// DIAG: expected vector literal digits
// CHECK: unsized 659 538623 3888{{$}}
// CHECK-NEXT: sized 1001 00011 01x xxxxxxxxxxxx zzzzzzzzzzzzzzzz{{$}}
// CHECK-NEXT: sign 250 -1 0001 zzzzzzzzzzzzzzzz{{$}}
// CHECK-NEXT: pad xxx 03x zz3 0z3{{$}}
// CHECK-NEXT: wide 0000000000000000000005 xxxxxxxxxxxxxxxxxxxxxx zzzzzzzzzzzzzzzzzzzzzz{{$}}
// CHECK-NEXT: fill 0000{{$}}
// CHECK-NEXT: fill ffff{{$}}
// CHECK-NEXT: fill xxxx{{$}}
// CHECK-NEXT: fill zzzz 1{{$}}
// CHECK-NEXT: z pad zzzzzzz1{{$}}
// CHECK-NEXT: truncate 0101{{$}}
// CHECK-NEXT: signed -8{{$}}
// CHECK-NEXT: unsigned 8{{$}}
// CHECK-NEXT: underscore 351f{{$}}
// CHECK-NEXT: width 1 1 1{{$}}

// 5.7.1: the clause's examples, with X and Z padding checked as printed digits.
module top;
  logic [11:0] a, b, c, d;
  logic [84:0] e, f, g;
  logic [15:0] u;
  logic [7:0] z8;
  int i;
  initial begin
    $display("unsized %0d %0d %0d", 659, 'h837FF, 'o7460);
    $display("sized %b %b %b %b %b", 4'b1001, 5 'D 3, 3'b01x, 12'hx, 16'hz);
    $display("sign %0d %0d %b %b", -8 'd 6, 4 'shf, -4 'sd15, 16'sd?);
    a = 'h x; b = 'h 3x; c = 'h z3; d = 'h 0z3;
    $display("pad %h %h %h %h", a, b, c, d);
    e = 'h5; f = 'hx; g = 'hz;
    $display("wide %h %h %h", e, f, g);
    u = '0; $display("fill %h", u);
    u = '1; $display("fill %h", u);
    u = 'x; $display("fill %h", u);
    u = 'z; $display("fill %h %0d", u, $bits('1));
    z8 = 8'bz1; $display("z pad %b", z8);
    $display("truncate %b", 4'b110101);
    i = 4'sb1000; $display("signed %0d", i);
    i = 4'b1000;  $display("unsigned %0d", i);
    $display("underscore %h", 16'b0011_0101_0001_1111);
    $display("width %b %b %b", $bits(659) >= 32, $bits('h7_0000_0000) >= 35, $bits(4294967296) >= 34);
    $finish;
  end
endmodule
