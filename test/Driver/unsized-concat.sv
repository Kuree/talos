// RUN: not talos -emit-slang %s 2>&1 | FileCheck %s
// RUN: talos -emit-slang -Wno-unsized-concat %s -o /dev/null
// RUN: talos -emit-slang -DSIZED %s -o /dev/null

// IEEE 1800-2023 11.4.12: unsized constants are not allowed in concatenations.
// -Wno-unsized-concat restores slang's guessed width for existing sources.
module top;
  logic [33:0] v;
`ifdef SIZED
  initial v = {32'd1, 2'b00};
`else
  // CHECK: error: unsized integer in concat; using a width of 32 [-Wunsized-concat]
  initial v = {1, 2'b00};
`endif
endmodule
