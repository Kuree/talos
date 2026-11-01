// RUN: talos -emit-slang %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: talos -emit-slang -DLOCAL %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=LOCAL
// RUN: talos -emit-slang -DPROCEDURAL %s | not talos-opt --convert-slang-to-talos --lower-talos-to-sim=opt-level=0 2>&1 | FileCheck %s --check-prefix=PROCEDURAL

// IEEE 1800-2023 16.12.5, 16.12.17: a property nesting implications or recursing
// has no bounded monitor. It compiles to an automaton whose state holds the count
// of live attempts, each stepped once per clock tick with the sampled atoms.
module top;
  bit clk, a, b, c, done;
`ifdef LOCAL
  // LOCAL: error:
  property p; int v; (a, v = 1) |-> (b |=> v == 1); endproperty
  assert property (@(posedge clk) p);
`elsif PROCEDURAL
  // PROCEDURAL: error:
  always @(posedge clk) assert property (a |-> not (##1 b));
`else
  property eventually_done;
    @(posedge clk) done or (1'b1 |=> eventually_done);
  endproperty
  assert property (eventually_done);
  assert property (@(posedge clk) a |-> (b |=> c));
`endif
endmodule

// The recursive property takes the automaton, whose attempts can end with the
// run either way. The bounded monitor fuses the nested implication, so it stays.
// CHECK-COUNT-1: simulation.code_unit.decl {{.*}}$concurrent_eos.{{[0-9]+}}.fail.automaton_fail
// CHECK-NOT: simulation.code_unit.decl {{.*}}$concurrent_eos.{{[0-9]+}}.fail.automaton_fail
