// CLAUSE: interconnect wire control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 6.6.8 (the clause example): one interconnect array carries a logic net to element 0 and a real nettype to element 1.
// CHECK-DAG: L in=1
// CHECK-DAG: R in=2.5

package NetsPkg; nettype real realNet; endpackage
module lDriver (output wire logic out); assign out = 1'b1; endmodule
module rDriver import NetsPkg::*; (output realNet out); assign out = 2.5; endmodule
module lMod (input wire logic in); initial #1 $display("L in=%b", in); endmodule
module rMod import NetsPkg::*; (input realNet in); initial #1 $display("R in=%0.1f", in); endmodule
module rlMod (input interconnect iBus[0:1]); lMod l1(iBus[0]); rMod r1(iBus[1]); endmodule
module top;
  interconnect iBus[0:1];
  lDriver l1(iBus[0]);  rDriver r1(iBus[1]);  rlMod m1(iBus);
endmodule
