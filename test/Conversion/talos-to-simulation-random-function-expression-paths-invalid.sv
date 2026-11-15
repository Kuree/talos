// RUN: %talos --std=1800-2023 -emit-talos %s | not talos-opt '--test-talos-edit-attributes=op=talos.sv.expression.named_value match={referenced_path = "C::y"} set={simulation.random_priority_condition = 0 : i64}' '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=OWNER
// RUN: %talos --std=1800-2023 -emit-talos %s | not talos-opt '--test-talos-edit-attributes=op=talos.sv.constraint.list match={item_count = 1 : i64} set={simulation.random_priority_contexts = [{parent = 1 : i64, condition = 0 : i64, positive = true, kind = 1 : i64}]}' '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=PARENT
// RUN: %talos --std=1800-2023 -emit-talos %s | not talos-opt '--test-talos-edit-attributes=op=talos.sv.constraint.list match={item_count = 1 : i64} set={simulation.random_priority_contexts = [{parent = 0 : i64, condition = 0 : i64, positive = true, kind = 0 : i64}]}' '--lower-talos-to-sim=opt-level=0' 2>&1 | FileCheck %s --check-prefix=KIND
// REQUIRES: compiled-sampler

// IEEE 1800-2023 18.5.11 implicit function ordering: the internal path
// metadata (priority conditions and branch contexts) is corrupted after the
// frontend. Invalid owners, forward parent links and wrongly typed context
// kinds must be diagnosed instead of being cast or trusted.
// OWNER: error: constraint priority condition metadata requires a conditional, logical or fixed-array selection expression
// PARENT: error: constraint function branch context metadata is malformed
// KIND: error: constraint function branch context kind is inconsistent

class C;
  rand bit x, y;
  function bit identity(bit v); return v; endfunction
  constraint relation { (x == identity(y)) && 1; }
endclass
module top; C o = new; initial void'(o.randomize()); endmodule
