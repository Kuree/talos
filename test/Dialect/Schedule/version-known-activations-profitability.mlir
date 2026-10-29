// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(schedule-version-known-activations)' | FileCheck %s
// RUN: talos-opt %s --split-input-file -mlir-disable-threading --pass-pipeline='builtin.module(schedule-version-known-activations)' -o /dev/null 2>&1 | FileCheck %s --check-prefix=COST
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(schedule-version-known-activations{checked-reads=true})' | FileCheck %s --check-prefix=DYNAMIC

// Nested activation copies compare savings beyond the outer inductive proof
// with their checks and unchanged copied work. Operations earning residual
// savings contribute no additional duplication penalty. The first function
// is profitable; the second has too much unchanged four-state arithmetic.
!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
!memory = !simulation.unpacked_array<0 : 7 x !l8>
module attributes {native.optimization_level = 3 : i32, native.debug_timing} {
  simulation.design @profitable {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l8 design
    simulation.storage.decl 1 in 0 : !l8 design
    simulation.storage.decl 2 in 0 : !memory design
    simulation.storage.decl 3 in 0 : !l8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.writes_x"
    simulation.func @writes_x(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %unknown = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.ref.store %unknown to %a : !l8, !r8
      simulation.return
    }
    // CHECK-LABEL: simulation.func @profitable
    // CHECK-SAME: schedule.eval.inductive_two_state
    // CHECK-SAME: schedule.native.known_activation
    // CHECK: schedule.known.roots
    // CHECK: simulation.ref.load %{{.*}} {schedule.native.known_read}
    // CHECK: simulation.ref.store %{{.*}} to %{{.*}} {schedule.native.known_store}
    // COST: talos nested activation cost: profitable segment=0 residual={{[0-9]+}} check={{[0-9]+}} unchanged=2 accepted=1
    simulation.func @profitable(%ctx: !c {simulation.capture_kind = 0 : i32}, %i: i64 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %x = simulation.ref.load %a : !r8 -> !l8
      %p0 = simulation.logic.binary mul %x, %x : !l8
      %p1 = simulation.logic.binary mul %p0, %x : !l8
      %p2 = simulation.logic.binary mul %p1, %x : !l8
      %p3 = simulation.logic.binary mul %p2, %x : !l8
      %p4 = simulation.logic.binary mul %p3, %x : !l8
      %p5 = simulation.logic.binary mul %p4, %x : !l8
      %p6 = simulation.logic.binary mul %p5, %x : !l8
      %p7 = simulation.logic.binary mul %p6, %x : !l8
      %p8 = simulation.logic.binary mul %p7, %x : !l8
      %p9 = simulation.logic.binary mul %p8, %x : !l8
      %p10 = simulation.logic.binary mul %p9, %x : !l8
      %p11 = simulation.logic.binary mul %p10, %x : !l8
      %p12 = simulation.logic.binary mul %p11, %x : !l8
      %p13 = simulation.logic.binary mul %p12, %x : !l8
      %p14 = simulation.logic.binary mul %p13, %x : !l8
      %p15 = simulation.logic.binary mul %p14, %x : !l8
      simulation.ref.store %p15 to %b : !l8, !r8
      // This coercion is free in the copy because the input is now known.
      %bits = simulation.logic.to_bits %p15 : !l8 -> i8
      %bits_out = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      simulation.ref.store %bits to %bits_out : i8, !simulation.ref<i8>
      simulation.return
    }
  }
}

// -----

!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
!memory = !simulation.unpacked_array<0 : 7 x !l8>
module attributes {native.optimization_level = 3 : i32, native.debug_timing} {
  simulation.design @bloated {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l8 design
    simulation.storage.decl 1 in 0 : !l8 design
    simulation.storage.decl 2 in 0 : !memory design
    simulation.storage.decl 3 in 0 : !l8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.writes_x"
    simulation.func @writes_x(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %unknown = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.ref.store %unknown to %a : !l8, !r8
      simulation.return
    }
    // CHECK-LABEL: simulation.func @bloated
    // CHECK-SAME: schedule.eval.inductive_two_state
    // CHECK-NOT: schedule.native.known_activation
    // CHECK-NOT: schedule.known.roots
    // CHECK: simulation.ref.load
    // CHECK-NOT: schedule.native.known_read
    // CHECK: simulation.return
    // COST: talos nested activation cost: bloated segment=0 residual={{[0-9]+}} check={{[0-9]+}} unchanged=81 accepted=0
    simulation.func @bloated(%ctx: !c {simulation.capture_kind = 0 : i32}, %i: i64 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %x = simulation.ref.load %a : !r8 -> !l8
      %p0 = simulation.logic.binary mul %x, %x : !l8
      %p1 = simulation.logic.binary mul %p0, %x : !l8
      %p2 = simulation.logic.binary mul %p1, %x : !l8
      %p3 = simulation.logic.binary mul %p2, %x : !l8
      %p4 = simulation.logic.binary mul %p3, %x : !l8
      %p5 = simulation.logic.binary mul %p4, %x : !l8
      %p6 = simulation.logic.binary mul %p5, %x : !l8
      %p7 = simulation.logic.binary mul %p6, %x : !l8
      %p8 = simulation.logic.binary mul %p7, %x : !l8
      %p9 = simulation.logic.binary mul %p8, %x : !l8
      %p10 = simulation.logic.binary mul %p9, %x : !l8
      %p11 = simulation.logic.binary mul %p10, %x : !l8
      %p12 = simulation.logic.binary mul %p11, %x : !l8
      %p13 = simulation.logic.binary mul %p12, %x : !l8
      %p14 = simulation.logic.binary mul %p13, %x : !l8
      %p15 = simulation.logic.binary mul %p14, %x : !l8
      simulation.ref.store %p15 to %b : !l8, !r8
      %mem = simulation.context.storage %ctx[2] : !simulation.ref<!memory>
      %d = simulation.context.storage %ctx[3] : !r8
      %slot = simulation.ref.array_element %mem[%i] : (!simulation.ref<!memory>, i64) -> !r8
      %e = simulation.ref.load %slot : !r8 -> !l8
      %q0 = simulation.logic.binary mul %e, %e : !l8
      %q1 = simulation.logic.binary mul %q0, %e : !l8
      %q2 = simulation.logic.binary mul %q1, %e : !l8
      %q3 = simulation.logic.binary mul %q2, %e : !l8
      %q4 = simulation.logic.binary mul %q3, %e : !l8
      %q5 = simulation.logic.binary mul %q4, %e : !l8
      %q6 = simulation.logic.binary mul %q5, %e : !l8
      %q7 = simulation.logic.binary mul %q6, %e : !l8
      %q8 = simulation.logic.binary mul %q7, %e : !l8
      %q9 = simulation.logic.binary mul %q8, %e : !l8
      %q10 = simulation.logic.binary mul %q9, %e : !l8
      %q11 = simulation.logic.binary mul %q10, %e : !l8
      simulation.ref.store %q11 to %d : !l8, !r8
      // An unproved four-to-two-state coercion still computes both planes.
      // Keep it live so the added copy must pay for its two instructions.
      %bits = simulation.logic.to_bits %q11 : !l8 -> i8
      %bits_out = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      simulation.ref.store %bits to %bits_out : i8, !simulation.ref<i8>
      simulation.return
    }
  }
}

// -----

// Reducing the unproved chain from twelve multiplies to nine makes the
// unchanged-work penalty affordable. The full copy costs 81 instruction
// units, so charging it would reject 82 <= 2*7+81. Its unchanged work costs
// 63, and the static policy admits 82 > 2*7+63. Keep the unproved read and
// coercion four-state while specializing the independent useful chain.
!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
!memory = !simulation.unpacked_array<0 : 7 x !l8>
module attributes {native.optimization_level = 3 : i32, native.debug_timing} {
  simulation.design @unchanged_work {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l8 design
    simulation.storage.decl 1 in 0 : !l8 design
    simulation.storage.decl 2 in 0 : !memory design
    simulation.storage.decl 3 in 0 : !l8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.writes_x"
    simulation.func @writes_x(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !r8
      %unknown = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.ref.store %unknown to %a : !l8, !r8
      simulation.return
    }
    // CHECK-LABEL: simulation.func @unchanged_work
    // CHECK-SAME: schedule.eval.inductive_two_state
    // CHECK-SAME: schedule.native.known_activation
    // CHECK: schedule.known.roots
    // CHECK: simulation.ref.load %{{.*}} {schedule.native.known_read}
    // CHECK: %[[SLOT:[0-9]+]] = simulation.ref.array_element
    // CHECK: simulation.ref.load %[[SLOT]] :
    // CHECK-NOT: schedule.native.known_read
    // CHECK: simulation.logic.binary mul
    // CHECK: simulation.logic.to_bits
    // COST: talos nested activation cost: unchanged_work segment=0 residual=82 check=7 unchanged=63 accepted=1
    simulation.func @unchanged_work(%ctx: !c {simulation.capture_kind = 0 : i32}, %i: i64 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %x = simulation.ref.load %a : !r8 -> !l8
      %p0 = simulation.logic.binary mul %x, %x : !l8
      %p1 = simulation.logic.binary mul %p0, %x : !l8
      %p2 = simulation.logic.binary mul %p1, %x : !l8
      %p3 = simulation.logic.binary mul %p2, %x : !l8
      %p4 = simulation.logic.binary mul %p3, %x : !l8
      %p5 = simulation.logic.binary mul %p4, %x : !l8
      %p6 = simulation.logic.binary mul %p5, %x : !l8
      %p7 = simulation.logic.binary mul %p6, %x : !l8
      %p8 = simulation.logic.binary mul %p7, %x : !l8
      %p9 = simulation.logic.binary mul %p8, %x : !l8
      %p10 = simulation.logic.binary mul %p9, %x : !l8
      %p11 = simulation.logic.binary mul %p10, %x : !l8
      %p12 = simulation.logic.binary mul %p11, %x : !l8
      %p13 = simulation.logic.binary mul %p12, %x : !l8
      %p14 = simulation.logic.binary mul %p13, %x : !l8
      %p15 = simulation.logic.binary mul %p14, %x : !l8
      simulation.ref.store %p15 to %b : !l8, !r8
      %mem = simulation.context.storage %ctx[2] : !simulation.ref<!memory>
      %d = simulation.context.storage %ctx[3] : !r8
      %slot = simulation.ref.array_element %mem[%i] : (!simulation.ref<!memory>, i64) -> !r8
      %e = simulation.ref.load %slot : !r8 -> !l8
      %q0 = simulation.logic.binary mul %e, %e : !l8
      %q1 = simulation.logic.binary mul %q0, %e : !l8
      %q2 = simulation.logic.binary mul %q1, %e : !l8
      %q3 = simulation.logic.binary mul %q2, %e : !l8
      %q4 = simulation.logic.binary mul %q3, %e : !l8
      %q5 = simulation.logic.binary mul %q4, %e : !l8
      %q6 = simulation.logic.binary mul %q5, %e : !l8
      %q7 = simulation.logic.binary mul %q6, %e : !l8
      %q8 = simulation.logic.binary mul %q7, %e : !l8
      simulation.ref.store %q8 to %d : !l8, !r8
      %bits = simulation.logic.to_bits %q8 : !l8 -> i8
      %bits_out = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      simulation.ref.store %bits to %bits_out : i8, !simulation.ref<i8>
      simulation.return
    }
  }
}

// -----

// The outer certificate already makes this destination and its stored value
// two-state. Omitting the unknown-plane store is already free under that
// proof, so another gate and copy cannot claim it as new work saved.
!c = !simulation.context
!l = !simulation.logic<4096>
!r = !simulation.ref<!l>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @proven_store {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    // CHECK-LABEL: simulation.func @proven_store
    // CHECK-SAME: schedule.eval.inductive_two_state
    // CHECK-NOT: schedule.native.known_activation
    // CHECK-NOT: schedule.known.roots
    // CHECK: simulation.return
    simulation.func @proven_store(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %a = simulation.context.storage %ctx[0] : !r
      %zero = simulation.logic.constant 0 : i4096, 0 : i4096 : !l
      simulation.ref.store %zero to %a : !l, !r
      simulation.return
    }
  }
}

// -----

// A first specialization still saves that store when it lacks the outer
// certificate. The nested-copy rule must not disable ordinary versioning.
!c = !simulation.context
!l = !simulation.logic<4096>
!r = !simulation.ref<!l>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @first_store {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    // CHECK-LABEL: simulation.func @first_store
    // CHECK-SAME: schedule.native.known_activation
    // CHECK: schedule.known.roots
    // CHECK: simulation.ref.store %{{.*}} to %{{.*}} {schedule.native.known_store}
    simulation.func @first_store(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %zero = simulation.logic.constant 0 : i4096, 0 : i4096 : !l
      simulation.ref.store %zero to %a : !l, !r
      simulation.return
    }
  }
}

// -----

// Bounded array reads already load only their value plane under the outer
// certificate. Their dependent arithmetic must earn no residual benefit.
// Previously, double-counting admitted a redundant copy with residual=81.
!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
!memory = !simulation.unpacked_array<0 : 3 x !l8>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @bounded_dynamic {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !memory design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    // CHECK-LABEL: simulation.func @bounded_dynamic
    // CHECK-NOT: schedule.native.known_activation
    // CHECK-NOT: schedule.known.roots
    // CHECK: simulation.ref.load
    // CHECK-NOT: schedule.native.known_read
    // CHECK: simulation.return
    // DYNAMIC-LABEL: simulation.func @bounded_dynamic
    // DYNAMIC-NOT: schedule.native.known_activation
    // DYNAMIC-NOT: schedule.known.roots
    // DYNAMIC-NOT: schedule.known.value
    // DYNAMIC: simulation.return
    simulation.func @bounded_dynamic(%ctx: !c {simulation.capture_kind = 0 : i32}, %selector: i2 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %mem = simulation.context.storage %ctx[0] : !simulation.ref<!memory>
      %i = arith.extui %selector : i2 to i64
      %slot = simulation.ref.array_element %mem[%i] : (!simulation.ref<!memory>, i64) -> !r8
      %x = simulation.ref.load %slot : !r8 -> !l8
      %p0 = simulation.logic.binary mul %x, %x : !l8
      %p1 = simulation.logic.binary mul %p0, %x : !l8
      %p2 = simulation.logic.binary mul %p1, %x : !l8
      %p3 = simulation.logic.binary mul %p2, %x : !l8
      %p4 = simulation.logic.binary mul %p3, %x : !l8
      %p5 = simulation.logic.binary mul %p4, %x : !l8
      %p6 = simulation.logic.binary mul %p5, %x : !l8
      %p7 = simulation.logic.binary mul %p6, %x : !l8
      %p8 = simulation.logic.binary mul %p7, %x : !l8
      %p9 = simulation.logic.binary mul %p8, %x : !l8
      %p10 = simulation.logic.binary mul %p9, %x : !l8
      %p11 = simulation.logic.binary mul %p10, %x : !l8
      %p12 = simulation.logic.binary mul %p11, %x : !l8
      %p13 = simulation.logic.binary mul %p12, %x : !l8
      %p14 = simulation.logic.binary mul %p13, %x : !l8
      %p15 = simulation.logic.binary mul %p14, %x : !l8
      simulation.ref.store %p15 to %slot : !l8, !r8
      simulation.return
    }
  }
}

// -----

// An invalid array selection can return X even when its root is known.
// A tested read must keep its value check and continue in the original body
// when that read holds X/Z; the outer proof cannot replace that fallback.
!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
!memory = !simulation.unpacked_array<0 : 3 x !l8>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @invalid_dynamic {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !memory design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    // CHECK-LABEL: simulation.func @invalid_dynamic
    // CHECK-NOT: schedule.native.known_activation
    // CHECK: simulation.ref.load
    // CHECK-NOT: schedule.native.known_read
    // CHECK: simulation.return
    // DYNAMIC-LABEL: simulation.func @invalid_dynamic
    // DYNAMIC-SAME: schedule.native.known_activation
    // DYNAMIC: simulation.ref.load
    // DYNAMIC-NOT: schedule.native.known_read
    // DYNAMIC: %[[READ:[0-9]+]] = simulation.ref.load
    // DYNAMIC-NEXT: %{{.*}} = schedule.known.value %[[READ]]
    // DYNAMIC-NEXT: cf.cond_br
    simulation.func @invalid_dynamic(%ctx: !c {simulation.capture_kind = 0 : i32}, %selector: i3 {simulation.capture_kind = 2 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %root = simulation.context.storage %ctx[0] : !simulation.ref<!memory>
      %i = arith.extui %selector : i3 to i64
      %slot = simulation.ref.array_element %root[%i] : (!simulation.ref<!memory>, i64) -> !r8
      %x = simulation.ref.load %slot : !r8 -> !l8
      %p0 = simulation.logic.binary mul %x, %x : !l8
      %p1 = simulation.logic.binary mul %p0, %x : !l8
      %p2 = simulation.logic.binary mul %p1, %x : !l8
      %p3 = simulation.logic.binary mul %p2, %x : !l8
      %p4 = simulation.logic.binary mul %p3, %x : !l8
      %p5 = simulation.logic.binary mul %p4, %x : !l8
      %p6 = simulation.logic.binary mul %p5, %x : !l8
      %p7 = simulation.logic.binary mul %p6, %x : !l8
      %p8 = simulation.logic.binary mul %p7, %x : !l8
      %p9 = simulation.logic.binary mul %p8, %x : !l8
      %p10 = simulation.logic.binary mul %p9, %x : !l8
      %p11 = simulation.logic.binary mul %p10, %x : !l8
      %p12 = simulation.logic.binary mul %p11, %x : !l8
      %p13 = simulation.logic.binary mul %p12, %x : !l8
      %p14 = simulation.logic.binary mul %p13, %x : !l8
      %p15 = simulation.logic.binary mul %p14, %x : !l8
      simulation.return %p15 : !l8
    }
  }
}

// -----

// A packed selection can synthesize X in its clipped portion of the result.
// A tested read must keep its value check and continue in the original body
// when that read holds X/Z; the outer proof cannot replace that fallback.
!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
!memory = !simulation.unpacked_array<0 : 3 x !l8>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @clipped_dynamic {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<16> design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.f"
    // CHECK-LABEL: simulation.func @clipped_dynamic
    // CHECK-NOT: schedule.native.known_activation
    // CHECK: simulation.ref.load
    // CHECK-NOT: schedule.native.known_read
    // CHECK: simulation.return
    // DYNAMIC-LABEL: simulation.func @clipped_dynamic
    // DYNAMIC-SAME: schedule.native.known_activation
    // DYNAMIC: simulation.ref.load
    // DYNAMIC-NOT: schedule.native.known_read
    // DYNAMIC: %[[READ:[0-9]+]] = simulation.ref.load
    // DYNAMIC-NEXT: %{{.*}} = schedule.known.value %[[READ]]
    // DYNAMIC-NEXT: cf.cond_br
    simulation.func @clipped_dynamic(%ctx: !c {simulation.capture_kind = 0 : i32}, %selector: i4 {simulation.capture_kind = 2 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.inductive_two_state} {
      %root = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<16>>
      %i = arith.extui %selector : i4 to i64
      %slot = simulation.ref.dyn_extract %root from %i : (!simulation.ref<!simulation.logic<16>>, i64) -> !r8
      %x = simulation.ref.load %slot : !r8 -> !l8
      %p0 = simulation.logic.binary mul %x, %x : !l8
      %p1 = simulation.logic.binary mul %p0, %x : !l8
      %p2 = simulation.logic.binary mul %p1, %x : !l8
      %p3 = simulation.logic.binary mul %p2, %x : !l8
      %p4 = simulation.logic.binary mul %p3, %x : !l8
      %p5 = simulation.logic.binary mul %p4, %x : !l8
      %p6 = simulation.logic.binary mul %p5, %x : !l8
      %p7 = simulation.logic.binary mul %p6, %x : !l8
      %p8 = simulation.logic.binary mul %p7, %x : !l8
      %p9 = simulation.logic.binary mul %p8, %x : !l8
      %p10 = simulation.logic.binary mul %p9, %x : !l8
      %p11 = simulation.logic.binary mul %p10, %x : !l8
      %p12 = simulation.logic.binary mul %p11, %x : !l8
      %p13 = simulation.logic.binary mul %p12, %x : !l8
      %p14 = simulation.logic.binary mul %p13, %x : !l8
      %p15 = simulation.logic.binary mul %p14, %x : !l8
      simulation.return %p15 : !l8
    }
  }
}
