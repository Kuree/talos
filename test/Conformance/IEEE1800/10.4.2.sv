// CLAUSE: Nonblocking assignment evaluates now and updates later; dynamic array elements are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.4.2/dynamic.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/10.4.2/automatic.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: nonblocking assignments to elements of dynamically sized arrays are not allowed
// DIAG: nonblocking assignment to automatic variable 'v' is not allowed
// CHECK: same step 0 1{{$}}
// CHECK-NEXT: swapped 1 0{{$}}
// CHECK-NEXT: last wins 2{{$}}
// CHECK-NEXT: t6 d=0{{$}}
// CHECK-NEXT: t8 d=10{{$}}
// CHECK-NEXT: '{5, 0}

// 10.4.2: the right side and the lvalue index are taken when the statement runs, the update comes in the NBA
// region, the statement does not block, and the last of several updates wins.
module top;
  timeunit 1ns; timeprecision 1ns;
  logic a = 0, b = 1;
  int c = 0, d = 0, e = 10, i = 0;
  int arr[2] = '{0, 0};
  initial begin
    a <= b; b <= a;
    $display("same step %b %b", a, b);
    #1 $display("swapped %b %b", a, b);
    c <= 1; c <= 2;
    #1 $display("last wins %0d", c);
    d <= #5 e;
    e = 20;
    #4 $display("t%0t d=%0d", $time, d);
    #2 $display("t%0t d=%0d", $time, d);
    arr[i] <= 5;
    i = 1;
    #1 $display("%p", arr);
    $finish;
  end
endmodule
