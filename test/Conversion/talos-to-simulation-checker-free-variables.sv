// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DUNPACKED %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=UNPACKED

// IEEE 1800-2023 17.7.2: active free checker variables are solved at each assume
// set clock event from the sampled values of everything else, with the current
// value as their own sampled value. An assignment makes a variable inactive, and
// a const one keeps its first value.
checker c(input bit clk, input bit [7:0] state);
  rand bit [7:0] value;
  rand bit [7:0] selected;
  rand bit gate, follow;
  rand const bit [7:0] fixed;
  rand bit [7:0] assigned;
`ifdef UNPACKED
  // UNPACKED: error: IEEE 1800-2023 17.7.2 free checker variables that are not packed are not executable yet
  rand bit elements[2];
`endif
  always_ff @(posedge clk) assigned <= state;
  m0: assume property (@(posedge clk) value == state);
  m1: assume property (@(posedge clk) selected[3:0] == 4'h5);
  m2: assume property (@(posedge clk) gate |=> follow);
  // A sampled value function is not a constraint, so this one is only checked.
  m3: assume property (@(posedge clk) $rose(gate) |-> follow);
  m4: assume property (@(posedge clk) assigned == fixed);
endchecker
module top;
  bit clk;
  bit [7:0] state;
  c inst(clk, state);
endmodule

// What the solve records of an antecedent is not an object of the design.
// CHECK-NOT: free_prior

// m0 reads the active variable as it is and the formal as sampled.
// CHECK: simulation.func private @unit_7(
// CHECK: simulation.ref.load %arg3
// CHECK: simulation.assert.sampled_read %arg0 from %arg2

// m1 reads a selection of the active variable as it is too.
// CHECK: simulation.func private @unit_8(
// CHECK-NOT: sampled_read
// CHECK: simulation.ref.extract %arg2
// CHECK-NOT: sampled_read
// CHECK: simulation.func private @unit_9.fork

// The solve waits for the clock, carrying the antecedent of m2 across the wait. It
// assigns value, selected, gate and follow only.
// CHECK: simulation.func private @unit_12(
// CHECK: simulation.suspend.edge posedge %arg1 to ^bb2(%{{[0-9]+}} : i1)
// CHECK: simulation.assert.sampled_read %arg0 from %arg2
// CHECK: simulation.random.solve
// CHECK: simulation.ref.store %{{[0-9]+}} to %arg3
// CHECK: simulation.ref.store %{{[0-9]+}} to %arg4
// CHECK: simulation.ref.store %{{[0-9]+}} to %arg5
// CHECK: simulation.ref.store %{{[0-9]+}} to %arg6
// CHECK-NOT: simulation.ref.store
// CHECK: simulation.ref.load %arg5
// CHECK-NOT: simulation.ref.store
// CHECK: }
