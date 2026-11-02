// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 \
// RUN:   | FileCheck %s

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @managed_store_two_state {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "top.write"

    simulation.class.decl @C id 1 {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.field @C_field of @C at 0 : !simulation.logic<4> {
      is_static = false, is_weak = false
    }

    simulation.func private @write(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@C>
          {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      %field = simulation.class.field_ref %this[@C_field]
          : !simulation.class_handle<@C>
          -> !simulation.managed_ref<!simulation.logic<4>, @C>
      %known = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.managed.store %known to %field
          : !simulation.logic<4>, !simulation.managed_ref<!simulation.logic<4>, @C>
      %deferred = simulation.logic.constant 6 : i4, 0 : i4 : !simulation.logic<4>
      simulation.managed.nba.enqueue %deferred to %field
          : (!simulation.logic<4>, !simulation.managed_ref<!simulation.logic<4>, @C>) -> ()
      %masked = simulation.logic.constant 7 : i4, 0 : i4 : !simulation.logic<4>
      %mask = simulation.logic.constant 9 : i4, 0 : i4 : !simulation.logic<4>
      simulation.managed.nba.enqueue_masked %masked to %field mask %mask
          : (!simulation.logic<4>, !simulation.managed_ref<!simulation.logic<4>, @C>, !simulation.logic<4>) -> ()
      %other = simulation.logic.constant 3 : i4, 0 : i4 : !simulation.logic<4>
      %sum = simulation.logic.binary add %other, %other : !simulation.logic<4>
      simulation.return
    }
  }
}

// A class field has a value and an unknown plane, so the known value written to it
// keeps both (kind 2, size 16): one plane would leave a prior X or Z in the field
// (IEEE 1800-2023 6.8). The unrelated local keeps compact one-plane bits (kind 1),
// which shows that specialization is active. Nonblocking writes, masked or not,
// keep both planes too.
// CHECK: function 0: id=1
// CHECK-COUNT-3: kind=2 flags=0 width=4
// CHECK: kind=1 flags=0 width=4
