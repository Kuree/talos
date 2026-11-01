// CLAUSE: Conditional, case and loop statements select and repeat the expected branches; stray break rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/12/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statement can only be used inside a loop
// CHECK: if 1{{$}}
// CHECK-NEXT: if x 4{{$}}
// CHECK-NEXT: case 6{{$}}
// CHECK-NEXT: casez 9{{$}}
// CHECK-NEXT: casex 13{{$}}
// CHECK-NEXT: loops 80 13{{$}}

// Clause 12: an X condition takes the else, case compares X exactly, casez and casex treat ? z x as wildcards.
module top;
  logic [3:0] v = 4'b1001;
  logic [3:0] u = 4'b10x1;
  int n = 0, k = 0;
  initial begin
    if (v[0]) n = 1; else n = 2;
    $display("if %0d", n);
    if (u[1]) n = 3; else n = 4;
    $display("if x %0d", n);
    case (u)
      4'b1001: n = 5;
      4'b10x1: n = 6;
      default: n = 7;
    endcase
    $display("case %0d", n);
    casez (v)
      4'b1?1?: n = 8;
      4'b1??1: n = 9;
      default: n = 10;
    endcase
    $display("casez %0d", n);
    casex (u)
      4'b0xxx: n = 11;
      4'b11xx: n = 12;
      4'b1zx1: n = 13;
      default: n = 14;
    endcase
    $display("casex %0d", n);
    n = 0;
    for (int i = 1; i <= 4; i++) n += i;
    repeat (3) n *= 2;
    while (k < 3) k++;
    do k += 10; while (k < 0);
    $display("loops %0d %0d", n, k);
    $finish;
  end
endmodule
