// CLAUSE: Assignment expressions return the value cast to the left side; rejected outside procedures
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.3.6/continuous.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.3.6/event.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: assignment expressions are not allowed in this context
// DIAG: assignment expressions are not allowed in this context
// CHECK: if taken a=7 b=7{{$}}
// CHECK-NEXT: if not taken a=0 c=2{{$}}
// CHECK-NEXT: chain a=5 b=5 c=5{{$}}
// CHECK-NEXT: cast to left a=15 r=15{{$}}
// CHECK-NEXT: left type sa=-1 r=-1{{$}}
// CHECK-NEXT: concat x=0 y=1 r=1{{$}}

// 11.3.6: the value returned is the right side cast to the left side's type, so truncation and sign both show.
module top;
  logic [3:0] a;
  logic signed [3:0] sa;
  int b = 6, c = 0, r;
  bit x, y;
  initial begin
    if ((a = b)) b = (a += 1);
    $display("if taken a=%0d b=%0d", a, b);
    b = 0;
    if ((a = b)) c = 1; else c = 2;
    $display("if not taken a=%0d c=%0d", a, c);
    a = (b = (c = 5));
    $display("chain a=%0d b=%0d c=%0d", a, b, c);
    r = (a = 8'hFF);
    $display("cast to left a=%0d r=%0d", a, r);
    r = (sa = 4'hF);
    $display("left type sa=%0d r=%0d", sa, r);
    r = ({x, y} = 3'b101);
    $display("concat x=%0d y=%0d r=%0d", x, y, r);
    $finish;
  end
endmodule
