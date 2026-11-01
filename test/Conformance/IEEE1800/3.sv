// CLAUSE: Module, program, interface, package, checker and primitive work together; a late timeunit is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: time scale declaration must come before all other items in scope
// CHECK: program saw 20{{$}}
// CHECK-NEXT: interface 34{{$}}
// CHECK-NEXT: primitive 1{{$}}
// CHECK-NEXT: package 10 20{{$}}
// CHECK-NEXT: checker 2{{$}}

// Clause 3: one value from each building block. The program runs after the module's NBA update, so it sees 20.
package pkg;
  parameter int P = 10;
  function automatic int twice(int v);
    return v * 2;
  endfunction
endpackage
interface bus;
  logic [7:0] d = 8'h21;
  modport m(input d);
endinterface
primitive inv(output o, input i);
  table
    0 : 1;
    1 : 0;
  endtable
endprimitive
checker ticks(logic clk_i);
  int n = 0;
  always_ff @(posedge clk_i) n <= n + 1;
  final $display("checker %0d", n);
endchecker
program prog(input int seen);
  initial $display("program saw %0d", seen);
  // 24.7: the simulation ends when every program has finished, so stay alive.
  initial #100 $finish;
endprogram
module sub(bus.m bi);
  int r;
  initial #1 r = bi.d + 1;
endmodule
module top;
  import pkg::*;
  int v = 0;
  logic i = 0, clk = 0;
  wire o;
  bus b();
  sub s(b);
  inv u(o, i);
  ticks c(clk);
  prog p(v);
  initial v <= twice(P);
  initial begin
    #1 clk = 1;
    #1 clk = 0;
    #1 clk = 1;
    #1 $display("interface %0d", s.r);
    $display("primitive %b", o);
    $display("package %0d %0d", P, twice(P));
    $finish;
  end
endmodule
