// RUN: talos-opt %s -split-input-file -mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{census=true}))' -o /dev/null 2>&1 | FileCheck %s --check-prefix=CENSUS
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' | FileCheck %s --check-prefix=KEEP

// Copies the readers must keep (IEEE 1800-2023 10.3.2): the net's value is
// not its driver's, something besides the readers observes the net, or the
// readers would see update events the net never had. Each case is otherwise
// the plain forwarding shape of simulation-forward-copy-processes.mlir.
// A tri0 net is pulled to 0 when its driver is z (IEEE 1800-2023 6.6.5).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @tri0
// KEEP: simulation.spawn @copy
module {
  simulation.design @tri0 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {resolution_kind = 5 : i32}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A tri1 net is pulled to 1 when its driver is z (6.6.5).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @tri1
// KEEP: simulation.spawn @copy
module {
  simulation.design @tri1 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {resolution_kind = 6 : i32}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A trireg net keeps its charge when its driver is z (6.6.4).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @trireg
// KEEP: simulation.spawn @copy
module {
  simulation.design @trireg {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {resolution_kind = 9 : i32}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A supply1 net is 1 whatever its driver drives (6.6.6).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @supply1
// KEEP: simulation.spawn @copy
module {
  simulation.design @supply1 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {resolution_kind = 8 : i32}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// Wired nets resolve through their own tables (6.6.3).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @wand
// KEEP: simulation.spawn @copy
module {
  simulation.design @wand {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {resolution_kind = 3 : i32}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A net delay postpones every update of the net (28.16).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @net_delay
// KEEP: simulation.spawn @copy
module {
  simulation.design @net_delay {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {propagation_delays = array<i64: 5, 5, 5>}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A pull driver resolves with the strength scale (6.6.1, 28.11).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=not a plain single-driver wire
// KEEP-LABEL: simulation.design @pull_driver
// KEEP: simulation.spawn @copy
module {
  simulation.design @pull_driver {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64, strength0 = 5 : i32, strength1 = 5 : i32}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// VPI may read the net itself.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=observable net
// KEEP-LABEL: simulation.design @observable
// KEEP: simulation.spawn @copy
module {
  simulation.design @observable {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {observability = 1 : i32}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// Toggle coverage counts the net's own transitions.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=toggle coverage
// KEEP-LABEL: simulation.design @toggle
// KEEP: simulation.spawn @copy
module {
  simulation.design @toggle {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design {coverage.toggle_observable}
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// $dumpvars selects nets by scope and depth, so any net may be dumped (21.7).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=waveform dump
// KEEP-LABEL: simulation.design @waveform
// KEEP: simulation.spawn @copy
module {
  simulation.design @waveform {
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
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %levels = arith.constant 0 : i64
      %scope = simulation.bytes.constant ""
      simulation.dump.vars %ctx, %levels, %scope : (!simulation.context, i64, !simulation.bytes) -> ()
      simulation.return
    }
  }
}

// -----

// A program writer leaves the copy pending in the Active region until the
// Reactive set drains (4.5), so a program reader still sees the old net.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=reactive reader
// KEEP-LABEL: simulation.design @reactive
// KEEP: simulation.spawn @copy
module {
  simulation.design @reactive {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
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
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64, domain = 1 : i32, home_region = 10 : i32} {
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64, domain = 1 : i32, home_region = 10 : i32} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A store in a loop that does not suspend repeats on one activation.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=transient source
// KEEP-LABEL: simulation.design @loop
// KEEP: simulation.spawn @copy
module {
  simulation.design @loop {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.storage.decl 2 in 0 : !simulation.logic<1> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %sel = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<1>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s, %sel) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<1>> -> !simulation.process
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
      // Accumulate so an extra activation observes the source transient.
      %old = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %next = simulation.logic.binary add %old, %v : !simulation.logic<4>
      simulation.ref.store %next to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %again = simulation.ref.load %sel : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %b = simulation.logic.is_true %again : !simulation.logic<1>
      cf.cond_br %b, ^body, ^wait
    }
  }
}

// -----

// `s = 0; wait (c); s = 5;`: a level wait whose condition already holds
// does not block (9.4.3), so both stores may share one activation.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=transient source
// KEEP-LABEL: simulation.design @level_wait
// KEEP: simulation.spawn @copy
module {
  simulation.design @level_wait {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.storage.decl 2 in 0 : !simulation.logic<1> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %sel = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<1>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s, %sel) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<1>> -> !simulation.process
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
      // Accumulate so an extra activation observes the source transient.
      %old = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %next = simulation.logic.binary add %old, %v : !simulation.logic<4>
      simulation.ref.store %next to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.ref.store %zero to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.level %sel to ^set : !simulation.ref<!simulation.logic<1>>
    ^set:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    }
  }
}

// -----

// A blocking and a nonblocking write of one root publish twice per step.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=transient source
// KEEP-LABEL: simulation.design @blocking_and_nonblocking
// KEEP: simulation.spawn @copy
module {
  simulation.design @blocking_and_nonblocking {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
      // Accumulate so an extra activation observes the source transient.
      %old = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %next = simulation.logic.binary add %old, %v : !simulation.logic<4>
      simulation.ref.store %next to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.ref.store %zero to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.nba.enqueue %five to %out : (!simulation.logic<4>, !simulation.ref<!simulation.logic<4>>) -> ()
      cf.br ^wait
    }
  }
}

// -----

// A task may store through its ref formal any number of times (13.5.2).
// CENSUS-LABEL: talos forward-copies: processes=5 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=transient source
// KEEP-LABEL: simulation.design @task_formal
// KEEP: simulation.spawn @copy
module {
  simulation.design @task_formal {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.code_unit.decl 5 in 0 task hierarchy "task"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
      // Accumulate so an extra activation observes the source transient.
      %old = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %next = simulation.logic.binary add %old, %v : !simulation.logic<4>
      simulation.ref.store %next to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.task.call @task(%ctx, %out) arguments 2 to ^wait : !simulation.context, !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @task(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %r: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 5 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %zero to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.ref.store %five to %r : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// Two processes' nonblocking writes of one bit commit in one NBA region and
// may publish both values before an Active process runs (4.4.2.4, 10.4.2).
// CENSUS-LABEL: talos forward-copies: processes=5 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=transient source
// KEEP-LABEL: simulation.design @two_nba_writers
// KEEP: simulation.spawn @copy
module {
  simulation.design @two_nba_writers {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.code_unit.decl 5 in 0 always hierarchy "other"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p3 = simulation.spawn @other(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
      // Accumulate so an extra activation observes the source transient.
      %old = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %next = simulation.logic.binary add %old, %v : !simulation.logic<4>
      simulation.ref.store %next to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.nba.enqueue %five to %out : (!simulation.logic<4>, !simulation.ref<!simulation.logic<4>>) -> ()
      cf.br ^wait
    }
    simulation.func private @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.nba.enqueue %five to %out : (!simulation.logic<4>, !simulation.ref<!simulation.logic<4>>) -> ()
      cf.br ^wait
    }
  }
}

// -----

// `assign y = a | b; always_comb begin o = 0; if (y) o = 1; end`: moved onto
// a and b, the reader would also run when y keeps its value and publish a
// 1 -> 0 -> 1 transient on o that y never caused (9.2.2.2.1, 9.4.2).
// Toggle coverage observes that transient, so the reader is not quiet.
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=wait on expression
// KEEP-LABEL: simulation.design @transient_reader
// KEEP: simulation.spawn @copy
module {
  simulation.design @transient_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design {coverage.toggle_observable}
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %a, %b, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %a) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %va = simulation.ref.load %a : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %vb = simulation.ref.load %b : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %v = simulation.logic.binary or %va, %vb : !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.any %a, %b edges [0, 0] to ^body : !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %t = simulation.logic.is_true %v : !simulation.logic<4>
      cf.cond_br %t, ^set, ^wait
    ^set:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    ^wait:
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// `always @(y) s = 5;` with `assign y = s`: on s it would wake on its own
// store; the copy keeps that ordering decision with the scheduler (9.4.2).
// CENSUS-LABEL: talos forward-copies: processes=4 copies=1 sinks=1 eligible=0
// CENSUS: blocked: count=1 reason=self-sensitive reader
// KEEP-LABEL: simulation.design @self_sensitive
// KEEP: simulation.spawn @copy
module {
  simulation.design @self_sensitive {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %s) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      cf.br ^body
    ^body:
      simulation.suspend.change %in to ^set : !simulation.net<!simulation.logic<4>>
    ^set:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}
