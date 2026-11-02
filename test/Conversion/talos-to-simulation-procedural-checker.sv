// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang %s | FileCheck %s --check-prefix=MARK

// IEEE 1800-2023 17.3, 17.4: a procedural checker instance's procedures run at
// every time step, on the clock of the instantiation when a formal infers it,
// while its static assertions are queued when the instantiation is reached.
checker c(input bit value, input event e = $inferred_clock);
  bit seen;
  always_ff @(e) seen <= value;
  a: assert property (@e value);
endchecker
module top;
  bit clk, en, value;
  always @(posedge clk) if (en) c inst(value);
endmodule

// The procedure of the checker waits on the clock of its context on its own.
// CHECK: simulation.func private @unit_0(
// CHECK: simulation.suspend.edge posedge %arg1
// CHECK: simulation.assert.sampled_read %arg0 from %arg2

// The enclosing procedure queues the assertion only when `en` holds.
// CHECK: simulation.func private @unit_1(
// CHECK: simulation.suspend.edge posedge %arg1
// CHECK: cf.cond_br
// CHECK: simulation.spawn @unit_1.fork

// Only the assertion of the procedural instance is marked to move.
// MARK-COUNT-1: is_from_assertion
// MARK-NOT: is_from_assertion
