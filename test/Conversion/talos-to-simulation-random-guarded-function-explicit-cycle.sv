// RUN: %split-file %s %t
// RUN: %talos --std=1800-2023 -emit-talos %t/exclusive.sv | talos-opt '--lower-talos-to-sim=opt-level=0' | FileCheck %s
// RUN: %talos --std=1800-2023 -emit-talos %t/implicit.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=ERR
// RUN: %talos --std=1800-2023 -emit-talos %t/explicit.sv | not talos-opt '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=ERR
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.9/18.5.11: the implicit ordering of function calls in
// mutually exclusive branches is a live-graph property, so it is not a
// declaration cycle. An unguarded implicit cycle (even next to a guarded copy)
// and a pair of explicit solve-before edges remain compile-time errors.
// CHECK: simulation.random.solve
// ERR: error: solve before ordering contains a cycle

//--- exclusive.sv
class C;
  rand bit x, y;
  bit enabled;
  function bit identity(bit v); return v; endfunction
  constraint guarded { if (enabled) x == identity(y); else y == identity(x); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- implicit.sv
class C;
  rand bit x, y;
  bit enabled;
  function bit identity(bit v); return v; endfunction
  constraint cyc { x == identity(y); y == identity(x); if (enabled) x == identity(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule

//--- explicit.sv
class C;
  rand bit x, y;
  bit enabled;
  function bit identity(bit v); return v; endfunction
  constraint cyc { solve x before y; solve y before x; if (enabled) x == identity(y); }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
