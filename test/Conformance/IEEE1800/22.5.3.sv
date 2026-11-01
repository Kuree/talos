// CLAUSE: undefineall
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.5.3: `undefineall removes every macro (R=0, neither A nor B defined) and later defines work again.
// CHECK: R=0 A=9

`define A 1
`define B 2
`undefineall
`ifdef A
`define R 1
`elsif B
`define R 1
`else
`define R 0
`endif
`define A 9
module top;
  initial $display("R=%0d A=%0d", `R, `A);
endmodule
