// RUN: talos -emit-slang %s | FileCheck %s

// A design that uses none of these features carries no record of them: not the
// delay mode of IEEE 1800-2023 E.4 to E.7, nor the mark that lets a procedural
// checker instance move its assertions (17.3).
checker c(input bit clk, input bit a);
  p: assert property (@(posedge clk) a);
endchecker
module top;
  bit clk, a;
  c check(clk, a);
  q: assert property (@(posedge clk) a);
endmodule

// CHECK-NOT: vpi_def_delay_mode
// CHECK-NOT: is_from_assertion
// CHECK: slang.symbol.root
// CHECK-NOT: vpi_def_delay_mode
// CHECK-NOT: is_from_assertion
