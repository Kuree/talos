// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang %s | FileCheck %s --check-prefix=MARK
// RUN: talos -emit-slang -DLOOP %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=LOOP

// IEEE 1800-2023 17.3, 17.4: a procedural checker instance's procedures run at
// every time step, on the clock of the instantiation when a formal infers it,
// while its static assertions are queued when the instantiation is reached.
`ifdef LOOP
// A child checker's static assertions count as instantiated in the parent, and
// each pass of the loop queues the parent's and the child's with the automatic
// values of that pass.
checker inner(event clk, logic [7:0] a);
  i: assert property (@clk a == 10) $display("inner");
endchecker
checker outer(event clk, logic [7:0] a, b);
  inner child(clk, a);
  p: assert property (@clk a != b) $display("outer");
endchecker
module top;
  bit clk;
  logic [7:0] in, values [0:20];
  always @(posedge clk) begin
    automatic logic [7:0] v = 0;
    for (int i = 0; i < 4; i++) begin
      v = v + 5;
      outer instance_in_loop(posedge clk, in, values[v]);
    end
  end
endmodule
`else
checker c(input bit value, input event e = $inferred_clock);
  bit seen;
  always_ff @(e) seen <= value;
  a: assert property (@e value);
endchecker
module top;
  bit clk, en, value;
  always @(posedge clk) if (en) c inst(value);
endmodule
`endif

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

// LOOP: simulation.func private @[[UNIT:unit_[0-9]+]](
// LOOP: simulation.suspend.edge posedge
// LOOP: cf.cond_br
// LOOP: %[[V:[0-9]+]] = simulation.packed.unflatten
// LOOP: simulation.spawn @[[UNIT]].fork
// LOOP: simulation.spawn @[[UNIT]].fork.{{[0-9.]+}}(%arg0, %[[V]],
// LOOP: cf.br ^bb{{[0-9]+}}(%[[V]],
