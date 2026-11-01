// CLAUSE: Functions return through their name or return and may not pass time
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.4/delay.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.4/task.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// DIAG: cannot invoke a task from within a function
// CHECK: name 10{{$}}
// CHECK-NEXT: wrap 0{{$}}
// CHECK-NEXT: return 8{{$}}
// CHECK-NEXT: implicit 0 1 1{{$}}
// CHECK-NEXT: void 7{{$}}
// CHECK-NEXT: output 4 6{{$}}
// CHECK-NEXT: recursion 120{{$}}
// CHECK-NEXT: static 2{{$}}

// 13.4: the implicit return type is a logic scalar, and return ends the function ahead of later assignments.
module top;
  int g = 0;
  function [7:0] inc(input [7:0] x);
    inc = x + 1;
  endfunction
  function int stops(int a);
    stops = 1;
    return a * 2;
    stops = 99;
  endfunction
  function implicit(int x);
    implicit = x;
  endfunction
  function void setg(int v);
    g = v;
  endfunction
  function automatic int both(int a, output int b);
    b = a + 1;
    return a - 1;
  endfunction
  function automatic int fact(int n);
    return n <= 1 ? 1 : n * fact(n - 1);
  endfunction
  function int counter();
    static int n = 0;
    n++;
    return n;
  endfunction
  int out, r;
  initial begin
    $display("name %0d", inc(8'd9));
    $display("wrap %0d", inc(8'd255));
    $display("return %0d", stops(4));
    $display("implicit %0d %0d %0d", implicit(2), implicit(3), $bits(implicit(1)));
    setg(7);
    $display("void %0d", g);
    r = both(5, out);
    $display("output %0d %0d", r, out);
    $display("recursion %0d", fact(5));
    void'(counter());
    $display("static %0d", counter());
    $finish;
  end
endmodule
