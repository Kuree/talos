// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos --talos-sim-prepare | FileCheck %s
// RUN: talos -DNO_CLOCK -emit-slang %s | not talos-opt --convert-slang-to-talos --talos-sim-prepare -o /dev/null 2>&1 | FileCheck %s --check-prefix=NO-CLOCK

// IEEE 1800-2023 16.14.7: $inferred_clock and $inferred_disable are replaced by
// the clock flowing to the instance and the default disable condition in scope
// where the property or sequence is instantiated.
`ifdef NO_CLOCK
module top;
  // NO-CLOCK: error: $inferred_clock has no current resolved event expression
  property p(event e = $inferred_clock);
    @e 1;
  endproperty
  a: assert property (p());
endmodule
`else
module top;
  bit clk, flowing, rst;
  default clocking cb @(posedge clk); endclocking
  default disable iff (rst);
  property p(event e = $inferred_clock, bit d = $inferred_disable);
    @e disable iff (d) 1;
  endproperty
  a: assert property (p());
  sequence s(event e = $inferred_clock);
    @e 1;
  endsequence
  b: assert property (@(posedge flowing) s());
endmodule

// The default clocking and the default disable condition.
// CHECK-LABEL: talos.sv.statement.concurrent_assertion
// CHECK: referenced_path = "top.p"
// CHECK-NEXT: talos.sv.assertion.clocking
// CHECK-NEXT: talos.sv.timing.signal_event attributes {edge_kind = 1
// CHECK-NEXT: talos.sv.expression.named_value {{.*}}referenced_path = "top.clk"
// CHECK: talos.sv.assertion.disable_iff
// CHECK-NEXT: talos.sv.expression.conversion
// CHECK-NEXT: talos.sv.expression.named_value {{.*}}referenced_path = "top.rst"

// The clock that flows to the instance through the property, not the default.
// CHECK-LABEL: talos.sv.statement.concurrent_assertion
// CHECK: referenced_path = "top.s"
// CHECK-NEXT: talos.sv.assertion.clocking
// CHECK-NEXT: talos.sv.timing.signal_event attributes {edge_kind = 1
// CHECK-NEXT: talos.sv.expression.named_value {{.*}}referenced_path = "top.flowing"
`endif
