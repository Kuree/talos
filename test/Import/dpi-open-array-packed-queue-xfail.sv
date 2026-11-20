// XFAIL: *
// Stock Slang rejects a queue bound to an open formal with a packed open dimension.
// RUN: %talos -emit-talos %s -o %t.mlir

module top;
  import "DPI-C" function void edit(inout logic [] logic_values[], inout bit [] bit_values[]);
  logic [5:0] logic_values[$];
  bit [1:0][2:0] bit_values[$];
  initial edit(logic_values, bit_values);
endmodule
