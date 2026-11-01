// CLAUSE: Operators evaluate on four-state operands at their context width; a zero slice size is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: value must be positive
// CHECK: add xxxx{{$}}
// CHECK-NEXT: and 0x00{{$}}
// CHECK-NEXT: eq x 1{{$}}
// CHECK-NEXT: cond 10xx{{$}}
// CHECK-NEXT: divmod -3 -1{{$}}
// CHECK-NEXT: power 1024{{$}}
// CHECK-NEXT: shift 11100000 00100000{{$}}
// CHECK-NEXT: reduce 0 0 1{{$}}
// CHECK-NEXT: context 0100 00{{$}}
// CHECK-NEXT: inside 1{{$}}

// Clause 11: a sample of arithmetic, X propagation, the merging conditional, signed shift and context width.
module top;
  logic [3:0] a = 4'b1x01;
  logic [7:0] p = 8'hff, q = 8'h01;
  logic [15:0] s;
  initial begin
    $display("add %b", a + 4'd1);
    $display("and %b", a & 4'b0110);
    $display("eq %b %b", a == 4'b1x01, a === 4'b1x01);
    $display("cond %b", 1'bx ? 4'b1010 : 4'b1001);
    $display("divmod %0d %0d", -7 / 2, -7 % 2);
    $display("power %0d", 2 ** 10);
    $display("shift %b %b", 8'sb1000_0000 >>> 2, 8'b1000_0000 >> 2);
    $display("reduce %b %b %b", &4'b1101, |4'b0000, ^4'b1101);
    s = p + q;
    $display("context %h %h", s, 8'(p + q));
    $display("inside %b", 4'd5 inside {4'd1, [4'd4:4'd6]});
    $finish;
  end
endmodule
