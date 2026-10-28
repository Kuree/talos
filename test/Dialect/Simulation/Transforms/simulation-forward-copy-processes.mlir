// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' | FileCheck %s
// RUN: talos-opt %s -mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{census=true}))' 2>&1 >/dev/null | FileCheck %s --check-prefix=CENSUS

// A copy process (an implied continuous assignment, IEEE 1800-2023 23.3.3,
// 10.3.2) forwards its source to a single-driver net. Its readers can read
// the source and wait on it instead (4.9.1, 9.4.2) when every writer of the
// source stores each bit at most once per activation, so the readers see
// exactly the update events the net would have had.
module {
  // CHECK-LABEL: simulation.design @plain
  // CHECK: simulation.func @root
  // CHECK-NOT: simulation.spawn @copy
  // CHECK: simulation.context.driver
  // CHECK-NEXT: %[[SRC:.*]] = simulation.context.storage %{{.*}}[0]
  // CHECK-NEXT: simulation.spawn @reader(%{{.*}}, %{{.*}}, %{{.*}}, %[[SRC]])
  // CHECK: simulation.func private @reader({{.*}}, %[[ARG:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
  // CHECK: simulation.ref.load %[[ARG]]
  // CHECK: simulation.suspend.change %[[ARG]]
  // CHECK-NOT: simulation.func private @copy
  // CENSUS: talos forward-copies: processes=4 copies=1 sinks=1 eligible=1 ready=1 ready_copies=1
  simulation.design @plain {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %n = simulation.logic.unary bit_not %v : (!simulation.logic<4>) -> !simulation.logic<4>
      simulation.ref.store %n to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }

  // `s = 0; if (sel) s = 5;` publishes a transient value on every activation
  // that the copy never forwarded (it runs after the writer): the readers keep
  // the net.
  // CHECK-LABEL: simulation.design @transient
  // CHECK: simulation.spawn @copy
  // CHECK: simulation.func private @copy
  // CHECK: simulation.func private @reader({{.*}}, %[[NET:.*]]: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %{{.*}})
  // CHECK: simulation.net.read %[[NET]]
  // CENSUS: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0 ready=0 ready_copies=0
  // CENSUS: talos forward-copies blocked: count=1 reason=transient source
  simulation.design @transient {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<1> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %sel = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<1>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %2 = simulation.spawn @writer(%ctx, %s, %sel) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    // `s = 0; if (sel) s = 5;`: the second store is reached after the first.
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %c = simulation.ref.load %sel : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %b = simulation.logic.is_true %c : !simulation.logic<1>
      cf.cond_br %b, ^set, ^wait
    ^set:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    ^wait:
      simulation.suspend.change %sel to ^body : !simulation.ref<!simulation.logic<1>>
    }
  }

  // An expression copy (`assign y = a & b`) is recomputed in an idempotent
  // combinational reader, which then waits on the operands.
  // CHECK-LABEL: simulation.design @expression
  // CHECK-NOT: simulation.spawn @copy
  // CHECK: simulation.func private @reader({{.*}}, %[[A:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %[[B:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64})
  // CHECK: %[[VA:.*]] = simulation.ref.load %[[A]]
  // CHECK: %[[VB:.*]] = simulation.ref.load %[[B]]
  // CHECK: simulation.logic.binary and %[[VA]], %[[VB]]
  // CHECK: simulation.suspend.any %[[A]], %[[B]] edges [0, 0]
  // CENSUS: talos forward-copies: processes=4 copies=1 sinks=1 eligible=1 ready=1 ready_copies=1
  simulation.design @expression {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %b = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %0 = simulation.spawn @copy(%ctx, %a, %b, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %2 = simulation.spawn @writer(%ctx, %a) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %va = simulation.ref.load %a : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %vb = simulation.ref.load %b : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %v = simulation.logic.binary and %va, %vb : !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.any %a, %b edges [0, 0] to ^body : !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}
