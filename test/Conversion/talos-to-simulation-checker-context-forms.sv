// RUN: talos -emit-slang -DCONVERSION %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=CONVERSION
// RUN: talos -emit-slang -DLIST %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=LIST
// RUN: talos -emit-slang -DDISABLE %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=DISABLE
// RUN: talos -emit-slang -DINSIDE %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=INSIDE
// RUN: talos -emit-slang -DTYPEDEF %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=TYPEDEF
// RUN: talos -emit-slang -DENDPOINT %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=ENDPOINT
// RUN: talos -emit-slang -DWIDE %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=WIDE
// RUN: talos -emit-slang -DCLOCKS %s | talos-opt --convert-slang-to-talos '--lower-talos-to-sim=opt-level=0' | FileCheck %s --check-prefix=CLOCKS

`ifdef CONVERSION
// IEEE 1800-2023 9.4.2: a `logic` formal reads a `bit` actual through a conversion
// with the edges of the actual, which a monitor can wait on directly.
checker c(logic clk, a);
  default clocking @(posedge clk); endclocking
  p: assert property (a);
endchecker
module top;
  bit clk, a;
  c inst(clk, a);
endmodule
`elsif LIST
// IEEE 1800-2023 16.14.6, 17.5: an instance reached without the clock waits for it,
// unless a member of the event list occurred in this time step (F.3.1).
module top;
  bit go, clk1, clk2, a;
  always @(posedge go) p: assert property (@(posedge clk1 or negedge clk2) a);
endmodule
`elsif DISABLE
// IEEE 1800-2023 16.14.7, 17.2: the default of a checker formal resolves in the
// context of the instantiation.
checker c(logic a, event clock = $inferred_clock, logic reset = $inferred_disable);
  p: assert property (@clock disable iff (reset) a);
endchecker
module top;
  bit clk, rst;
  logic a;
  default disable iff rst;
  always @(posedge clk) c inst(a);
endmodule
`elsif INSIDE
// IEEE 1800-2023 11.4.13, 16.5.1: every element of an array of state contributes
// its sampled value.
module top;
  bit clk;
  bit [7:0] v;
  int un[3:4];
  p: assert property (@(posedge clk) v inside {un});
endmodule
`elsif TYPEDEF
// The instance wrapper of a checker body is transparent to a typedef's identity.
checker c(input bit clk);
  typedef struct { int f; } us_t;
  us_t us = '{3};
  p: assert property (@(posedge clk) us.f == 3);
endchecker
module top;
  bit clk;
  c inst(clk);
endmodule
`elsif ENDPOINT
// IEEE 1800-2023 16.13.6: an `iff` makes no tick of a false condition, for an end
// point too.
module top;
  bit clk, en, a, b;
  sequence s; @(posedge clk iff en) a ##1 b; endsequence
  c: cover property (@(posedge clk iff en) s.triggered);
endmodule
`elsif WIDE
// IEEE 1800-2023 17.7.2: a random initial value fills every word of the variable.
checker c(input bit clk);
  rand bit [99:0] v;
  m: assume property (@(posedge clk) v[99:92] == 8'h5a);
endchecker
module top;
  bit clk;
  c inst(clk);
endmodule
`elsif CLOCKS
// IEEE 1800-2023 17.7.2: each assume set clock event solves on its own.
checker c(input bit c0, input bit c1);
  rand bit [7:0] v;
  m0: assume property (@(posedge c0) v[0] == 1);
  m1: assume property (@(posedge c1) v[1] == 1);
endchecker
module top;
  bit c0, c1;
  c inst(c0, c1);
endmodule
`endif

// CONVERSION: simulation.storage.decl 0 in {{.*}}"top.clk"
// CONVERSION: simulation.func private @{{unit_[0-9]+}}({{.*}}%[[CLOCK:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 0 : i64}
// CONVERSION: simulation.suspend.edge posedge %[[CLOCK]]

// LIST: simulation.clocking_output.current posedge
// LIST-NEXT: simulation.clocking_output.current negedge
// LIST-NEXT: %[[ANY:[0-9]+]] = arith.ori
// LIST-NEXT: cf.cond_br %[[ANY]]

// The attempt reads the instantiation's condition, as it is.
// DISABLE: simulation.storage.decl 1 in {{.*}}"top.rst"
// DISABLE: simulation.func private @unit_0.fork.{{[0-9]+}}.0.48({{.*}}%[[RST:arg[0-9]+]]: !simulation.ref<i1> {{{[^}]*}}descriptor_id = 1 : i64}
// DISABLE: simulation.ref.load %[[RST]]

// INSIDE: %[[FIRST:[0-9]+]] = simulation.ref.subelement %{{.*}}{{\[\[}}0{{\]\]}}
// INSIDE-NEXT: simulation.assert.sampled_read %arg0 from %[[FIRST]]
// INSIDE: %[[SECOND:[0-9]+]] = simulation.ref.subelement %{{.*}}{{\[\[}}1{{\]\]}}
// INSIDE-NEXT: simulation.assert.sampled_read %arg0 from %[[SECOND]]

// TYPEDEF: simulation.storage.decl {{[0-9]+}} in {{.*}}"top.inst.us"

// ENDPOINT: simulation.suspend.edge_iff posedge {{.*}}resume_region = 8
// ENDPOINT: simulation.suspend.edge_iff posedge {{.*}}resume_region = 9

// WIDE: simulation.random.next
// WIDE: simulation.random.next

// CLOCKS: simulation.storage.decl 0 in {{.*}}"top.c0"
// CLOCKS: simulation.storage.decl 1 in {{.*}}"top.c1"
// CLOCKS: simulation.suspend.edge posedge %arg1 {{.*}}repeating_always_wait
// CLOCKS: simulation.ref.store %{{[0-9]+}} to %arg2
// CLOCKS: simulation.suspend.edge posedge %arg1 {{.*}}repeating_always_wait
// CLOCKS: simulation.ref.store %{{[0-9]+}} to %arg2
