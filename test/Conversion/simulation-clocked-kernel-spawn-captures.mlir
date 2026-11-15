// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-activation-phases{effect-roots=true})' -o /dev/null 2>&1 | FileCheck %s --check-prefix=ROOTS

// IEEE 1800-2023 9.3.2, 13.5.2, 23.3.3: a fork captures the actual reference,
// so a private counter stays private even when forwarded by another fork. The
// members watch a port copy of the clock that the root initializer sets by call.
// ROOTS-LABEL: phases accepted_captures valid=1
// ROOTS: @worker:{{.*}} writes=local
// CHECK-LABEL: simulation.design @accepted_captures
// CHECK: simulation.spawn @clock_port
// CHECK: simulation.spawn @[[KERNEL:__talos_clocked_[0-9_]+]]
// CHECK: simulation.func private @[[KERNEL]]
// CHECK: simulation.suspend.edge posedge %{{.*}} : !simulation.ref<!simulation.logic<1>>
// CHECK: simulation.ref.store
// CHECK-NOT: simulation.nba.enqueue
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @accepted_captures {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.storage.decl 2 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.code_unit.decl 4 in 0 fork hierarchy "relay"
  simulation.code_unit.decl 5 in 0 fork hierarchy "worker"
  simulation.code_unit.decl 6 in 0 function hierarchy "initialize_clock"
  simulation.code_unit.decl 7 in 0 port_input hierarchy "clock_port"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %pin = simulation.context.storage %ctx[2] : !r
    %zero = simulation.logic.constant false, false : !b
    %counter = simulation.ref.alloc %zero : !b -> !r
    simulation.call @initialize_clock(%ctx) : (!simulation.context) -> ()
    %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !r -> !simulation.process
    %p = simulation.spawn @clock_port(%ctx, %clk, %pin) : !simulation.context, !r, !r -> !simulation.process
    %p1 = simulation.spawn @first(%ctx, %pin, %q0) : !simulation.context, !r, !r -> !simulation.process
    %p3 = simulation.spawn @relay(%ctx, %clk, %counter) : !simulation.context, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
    %d = simulation.time.constant 5
    simulation.suspend.delay %d to ^toggle
  ^toggle:
    %v = simulation.ref.load %clk : !r -> !b
    %n = simulation.logic.unary bit_not %v : (!b) -> !b
    simulation.ref.store %n to %clk : !b, !r
    simulation.suspend.delay %d to ^toggle
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body : !r
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
  simulation.func private @relay(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %counter: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64} {
    %w = simulation.spawn @worker(%ctx, %clk, %counter) : !simulation.context, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @worker(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %counter: !r {simulation.capture_kind = 1 : i32, simulation.automatic_reference_capture}) attributes {entry_kind = 13 : i32, code_unit_id = 5 : i64, home_region = 10 : i32} {
    %zero = simulation.logic.constant false, false : !b
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body {resume_region = 10 : i32} : !r
  ^body:
    simulation.ref.store %zero to %counter : !b, !r
    cf.br ^wait
  }
  simulation.func private @initialize_clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
    %clk = simulation.context.storage %ctx[0] : !r
    %zero = simulation.logic.constant false, false : !b
    simulation.ref.store %zero to %clk : !b, !r
    simulation.return
  }
  simulation.func private @clock_port(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 9 : i32, code_unit_id = 7 : i64} {
    cf.br ^copy
  ^copy:
    %v = simulation.ref.load %src : !r -> !b
    simulation.ref.store %v to %dst : !b, !r
    simulation.suspend.change %src to ^copy : !r
  }
}

// -----
// IEEE 1800-2023 13.5.2: join all entries of a formal. `shared` also gets
// the clock itself, `opaque` has an entry the analysis cannot see and `loop`
// forks itself; each stays conservative, so no kernel forms.
// ROOTS-LABEL: phases retained_captures valid=1
// ROOTS: @shared:{{.*}} writes=s0,
// ROOTS: @opaque:{{.*}} writes=unknown
// ROOTS: @loop:{{.*}} writes=unknown
// CHECK-LABEL: simulation.design @retained_captures
// CHECK-NOT: __talos_clocked_
// CHECK: simulation.nba.enqueue
// CHECK-NOT: __talos_clocked_
!b = !simulation.logic<1>
!r = !simulation.ref<!b>
simulation.design @retained_captures {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !b design
  simulation.storage.decl 1 in 0 : !b design
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 always hierarchy "clock"
  simulation.code_unit.decl 3 in 0 always_ff hierarchy "first"
  simulation.code_unit.decl 4 in 0 fork hierarchy "shared"
  simulation.code_unit.decl 5 in 0 fork hierarchy "opaque"
  simulation.code_unit.decl 6 in 0 fork hierarchy "loop"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64, test.opaque_entry = @opaque} {
    %clk = simulation.context.storage %ctx[0] : !r
    %q0 = simulation.context.storage %ctx[1] : !r
    %zero = simulation.logic.constant false, false : !b
    %counter = simulation.ref.alloc %zero : !b -> !r
    %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !r -> !simulation.process
    %p1 = simulation.spawn @first(%ctx, %clk, %q0) : !simulation.context, !r, !r -> !simulation.process
    %p3 = simulation.spawn @shared(%ctx, %clk, %counter) : !simulation.context, !r, !r -> !simulation.process
    %p4 = simulation.spawn @shared(%ctx, %clk, %clk) : !simulation.context, !r, !r -> !simulation.process
    %p5 = simulation.spawn @opaque(%ctx, %clk, %counter) : !simulation.context, !r, !r -> !simulation.process
    %p6 = simulation.spawn @loop(%ctx, %clk, %counter) : !simulation.context, !r, !r -> !simulation.process
    simulation.return
  }
  simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
    %d = simulation.time.constant 5
    simulation.suspend.delay %d to ^toggle
  ^toggle:
    %v = simulation.ref.load %clk : !r -> !b
    %n = simulation.logic.unary bit_not %v : (!b) -> !b
    simulation.ref.store %n to %clk : !b, !r
    simulation.suspend.delay %d to ^toggle
  }
  simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body : !r
  ^body:
    %old = simulation.ref.load %q : !r -> !b
    %next = simulation.logic.unary bit_not %old : (!b) -> !b
    simulation.nba.enqueue %next to %q : (!b, !r) -> ()
    cf.br ^wait
  }
  simulation.func private @shared(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %counter: !r {simulation.capture_kind = 1 : i32, simulation.automatic_reference_capture}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 10 : i32} {
    %zero = simulation.logic.constant false, false : !b
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body {resume_region = 10 : i32} : !r
  ^body:
    simulation.ref.store %zero to %counter : !b, !r
    cf.br ^wait
  }
  simulation.func private @opaque(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %counter: !r {simulation.capture_kind = 1 : i32, simulation.automatic_reference_capture}) attributes {entry_kind = 13 : i32, code_unit_id = 5 : i64, home_region = 10 : i32} {
    %zero = simulation.logic.constant false, false : !b
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body {resume_region = 10 : i32} : !r
  ^body:
    simulation.ref.store %zero to %counter : !b, !r
    cf.br ^wait
  }
  simulation.func private @loop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %counter: !r {simulation.capture_kind = 1 : i32, simulation.automatic_reference_capture}) attributes {entry_kind = 13 : i32, code_unit_id = 6 : i64, home_region = 10 : i32} {
    %zero = simulation.logic.constant false, false : !b
    cf.br ^wait
  ^wait:
    simulation.suspend.edge posedge %clk to ^body {resume_region = 10 : i32} : !r
  ^body:
    simulation.ref.store %zero to %counter : !b, !r
    %next = simulation.spawn @loop(%ctx, %clk, %counter) : !simulation.context, !r, !r -> !simulation.process
    cf.br ^wait
  }
}

