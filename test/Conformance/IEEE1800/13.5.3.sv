// CLAUSE: Default arguments are evaluated per call in the declaring scope; required arguments stay required
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.5.3/none.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/13.5.3/hole.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: too few arguments for 'rd'; expected 3 but 0 were provided
// DIAG: argument 'k' cannot be empty because it does not have a default value
// CHECK: rd 0 5 1{{$}}
// CHECK-NEXT: rd 2 5 1{{$}}
// CHECK-NEXT: rd 0 5 1{{$}}
// CHECK-NEXT: rd 0 5 7{{$}}
// CHECK-NEXT: rd 1 5 2{{$}}
// CHECK-NEXT: each call 11 12{{$}}
// CHECK-NEXT: not used 5 g=12{{$}}
// CHECK-NEXT: declaring scope 1{{$}}
// CHECK-NEXT: output default u.a=1 a=0{{$}}

// 13.5.3: a default runs only when used, again at each such call, and binds names where the task is declared.
module m;
  logic a = 0;
  task t1(output logic o = a);
    o = 1;
  endtask
endmodule
module top;
  int g = 10;
  int x = 1;
  logic a = 0;
  m u();
  function automatic int next();
    g++;
    return g;
  endfunction
  function automatic int f(int v = next());
    return v;
  endfunction
  function automatic int h(int v = x);
    return v;
  endfunction
  task automatic rd(int j = 0, int k, int data = 1);
    $display("rd %0d %0d %0d", j, k, data);
  endtask
  initial begin
    rd(, 5);
    rd(2, 5);
    rd(, 5, );
    rd(, 5, 7);
    rd(1, 5, 2);
    $display("each call %0d %0d", f(), f());
    $display("not used %0d g=%0d", f(5), g);
    begin
      int x = 7;
      $display("declaring scope %0d", h());
    end
    u.t1();
    $display("output default u.a=%b a=%b", u.a, a);
    $finish;
  end
endmodule
