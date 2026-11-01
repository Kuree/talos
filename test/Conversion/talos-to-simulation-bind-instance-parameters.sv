// RUN: talos -emit-slang %s | FileCheck %s --check-prefix=SLANG
// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 23.11: an instance-targeted bind adds its instance to one
// instance of the target definition and evaluates parameter actuals in that
// target's scope. The parameter assignment is not part of the definition, whose
// other instances do not have it, so it is not recorded as shared source syntax.
module Leaf #(parameter int K = 1);
endmodule
module Tap #(parameter int EXPECTED = 0);
  int seen = EXPECTED;
endmodule
module top;
  localparam int K = 99;
  Leaf #(7) one();
  Leaf #(9) two();
  bind one Tap #(.EXPECTED(K)) tap();
endmodule

// Only the actuals of the two instances that top's definition declares.
// SLANG-COUNT-2: slang.sv.source.parameter_actual
// SLANG-NOT: slang.sv.source.parameter_actual

// The target's K, not the K of the scope with the bind directive.
// CHECK: simulation.storage.decl {{[0-9]+}} in {{[0-9]+}} : i32 design hierarchy "top.one.tap.seen"
// CHECK-NOT: hierarchy "top.two.tap
// CHECK: simulation.func private @unit_0
// CHECK: arith.constant 7 : i32
