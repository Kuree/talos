// CLAUSE: undef
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 22.5.2: after `undef the macro is not defined (R=2), an undefined name is accepted, and it can be defined again (X=7).
// CHECK: R=2 X=7

`define X 1
`undef X
`ifdef X
`define R 1
`else
`define R 2
`endif
`undef NEVER_DEFINED
`define X 7
module top;
  initial $display("R=%0d X=%0d", `R, `X);
endmodule
