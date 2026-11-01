// CLAUSE: Constructors chain to the base, then initialize properties, then run their body; a delay in new is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.7/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// CHECK: base 1 2 3{{$}}
// CHECK-NEXT: derived 4 2 10{{$}}
// CHECK-NEXT: implicit 12{{$}}

// 8.7: d2 reads 2 because the base constructor ran first, and d3 is 10 because the body runs after the initializers.
class C;
  int c1 = 1;
  int c2 = 1;
  int c3 = 1;
  function new(int a);
    c2 = 2;
    c3 = a;
  endfunction
endclass
class D extends C;
  int d1 = 4;
  int d2 = c2;
  int d3 = 6;
  function new;
    super.new(3);
    d3 = d3 + d1;
  endfunction
endclass
class Implicit;
  int v = 12;
endclass
module top;
  D d;
  Implicit i;
  initial begin
    d = new;
    $display("base %0d %0d %0d", d.c1, d.c2, d.c3);
    $display("derived %0d %0d %0d", d.d1, d.d2, d.d3);
    i = new;
    $display("implicit %0d", i.v);
    $finish;
  end
endmodule
