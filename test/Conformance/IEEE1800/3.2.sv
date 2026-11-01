// CLAUSE: program reactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=cfg -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 3.2: module, interface, program, package, primitive and config design elements all take part in one design.
// CHECK-DAG: MOD M=4 sig=3
// CHECK-DAG: PRG sig+1=4
// CHECK-DAG: PK f(4)=5 UDP n=1

package pk; localparam int PV = 1; function int f(int x); return x + PV; endfunction endpackage
interface ifc; int sig = 3; endinterface
primitive inv (output o, input i); table 0 : 1; 1 : 0; endtable endprimitive
module mod #(parameter int M = 4) (ifc i); initial #1 $display("MOD M=%0d sig=%0d", M, i.sig); endmodule
program prg (ifc i); initial begin #1; $display("PRG sig+1=%0d", i.sig + 1); end endprogram
module top;
  ifc i();  mod m(i);  prg p(i);
  reg a = 0;  wire n;  inv u(n, a);
  initial begin #1; $display("PK f(4)=%0d UDP n=%b", pk::f(4), n); end
endmodule
config cfg; design work.top; default liblist work; endconfig
