// XFAIL: *
// Stock Slang rejects the inner queue binding specified by 35.5.6.1 and H.2.
// RUN: %talos -emit-talos %s -o %t.mlir

module top;
  import "DPI-C" function void edit(inout int rows[][]);
  int rows[][$];
  initial edit(rows);
endmodule
