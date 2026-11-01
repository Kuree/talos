// CLAUSE: Vector ranges address bits in any direction and arithmetic is modulo; a nonconstant bound is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.9.1/variable.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.9.1/unknown.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: reference to non-constant variable 'n' is not allowed in a constant expression
// DIAG: value must not have any unknown bits
// CHECK: bounds -1 4 6{{$}}
// CHECK-NEXT: descending 1 0{{$}}
// CHECK-NEXT: ascending 1 0{{$}}
// CHECK-NEXT: negative 1 0 1 0{{$}}
// CHECK-NEXT: sign -8 8{{$}}
// CHECK-NEXT: modulo 0{{$}}

// 6.9.1: the left bound is the MSB whichever way it runs, so each select depends on the declared range.
module top;
  logic [3:0] v = 4'b1010;
  logic [-1:4] b = 6'b101100;
  logic [0:3] asc = 4'b1000;
  logic signed [3:0] s = 4'b1000;
  logic [3:0] u = 4'b1000;
  logic [3:0] w = 4'd15;
  initial begin
    $display("bounds %0d %0d %0d", $left(b), $right(b), $bits(b));
    $display("descending %b %b", v[3], v[0]);
    $display("ascending %b %b", asc[0], asc[3]);
    $display("negative %b %b %b %b", b[-1], b[0], b[1], b[4]);
    $display("sign %0d %0d", s, u);
    w = w + 1;
    $display("modulo %0d", w);
    $finish;
  end
endmodule
