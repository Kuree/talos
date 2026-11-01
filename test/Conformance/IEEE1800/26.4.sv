// CLAUSE: module header package types
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 26.4: package items imported in a module header define the port type (8-bit wrap: 254+3=1) and the parameter default (3, overridden to 5).
// CHECK: r1=10 r2=1 r3=12 W=3,5

package P; typedef bit [7:0] Byte; parameter int N = 3; endpackage
module child import P::*; #(parameter int W = N) (input Byte data, output Byte result);
  assign result = data + W;
endmodule
module top;
  P::Byte d1 = 7, d2 = 254;  wire [7:0] r1, r2, r3;
  child u1(d1, r1);  child u2(d2, r2);  child #(.W(5)) u3(d1, r3);
  initial begin #1; $display("r1=%0d r2=%0d r3=%0d W=%0d,%0d", r1, r2, r3, u1.W, u3.W); end
endmodule
