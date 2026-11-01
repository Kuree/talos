// CLAUSE: Tasks and functions pass input, output, inout and ref arguments; const ref writes are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot assign to read-only variable 'x'
// CHECK: t=5 a=1 b=101 c=30 d=400{{$}}
// CHECK-NEXT: function 42 5 6{{$}}
// CHECK-NEXT: swap 101 1{{$}}

// Clause 13: a timed task returns later, and each argument mode shows its own copy semantics.
module top;
  timeunit 1ns; timeprecision 1ns;
  int a = 1, b = 2, c = 3, d = 4;
  task automatic modes(input int i, output int o, inout int io, ref int r);
    #5;
    i = 100;
    o = i + 1;
    io = io * 10;
    r = r * 100;
  endtask
  function automatic int add(int x, int y = 40);
    return x + y;
  endfunction
  function automatic void swap(ref int x, ref int y);
    int t = x;
    x = y;
    y = t;
  endfunction
  initial begin
    modes(a, b, c, d);
    $display("t=%0t a=%0d b=%0d c=%0d d=%0d", $time, a, b, c, d);
    $display("function %0d %0d %0d", add(2), add(2, 3), add(.y(1), .x(5)));
    swap(a, b);
    $display("swap %0d %0d", a, b);
    $finish;
  end
endmodule
