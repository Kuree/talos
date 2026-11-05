// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true}))' -o %t.mlir 2> %t.log
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REPORT < %t.log

// IEEE 1800-2023 9.4.2, Table 9-2: one value change is a posedge, a negedge or
// neither, never both. When every root of a clock class changes at most once
// per time slot after time zero (one periodic writer, which runs at most once
// per slot, 4.4.2.3 and 4.5, storing the class once per activation; copies
// follow it, 10.3.2 and 23.3.3), the members of the opposite edge never run in
// a later slot of a kernel. Their reads of the kernel's roots then cannot
// follow its direct stores. simulation-clocked-kernel-opposite-edge-time-zero
// covers the time-zero slot and simulation-clocked-kernel-opposite-edge-blockers
// classes that may change twice in a slot.

// `fall` reads `q`, which the posedge kernel updates. The clock stores once
// per activation, so `q` and `r` are both stored directly. The testbench delay
// reads both roots, so both kernels are deferred.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @opposite_edge {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "fall"
    simulation.code_unit.decl 5 in 0 initial hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @fall(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.ref.store %one to %clk : !bit, !ref
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^low
    }
    // CHECK-LABEL: simulation.design @opposite_edge
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_1_0
    // CHECK: simulation.suspend.edge posedge
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: simulation.ref.store
    // CHECK: }
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_2_0
    // CHECK: simulation.suspend.edge negedge
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: simulation.ref.store
    // CHECK: }
    // REPORT: talos clocked kernel class 0: once per slot
    // REPORT: talos clocked kernel: __talos_clocked_0_1_0 members=1 eligible=1 retained=0 snapshots=0 deferred=1
    // REPORT-NEXT: talos clocked kernel: __talos_clocked_0_2_0 members=1 eligible=1 retained=0 snapshots=0 deferred=1
    // REPORT-NOT: rejection
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @fall(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %q : !ref -> !bit
      %old = simulation.ref.load %r : !ref -> !bit
      %next = simulation.logic.binary xor %v, %old : !bit
      simulation.nba.enqueue %next to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %delay = simulation.time.constant 1000
      simulation.suspend.delay %delay to ^done
    ^done:
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %qv = simulation.ref.load %q : !ref -> !bit
      %rv = simulation.ref.load %r : !ref -> !bit
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "%b %b"
      simulation.display %ctx to %stdout(%format, %qv, %rv) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !bit, !bit
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}


// -----

// Without the testbench reader both kernels run immediately, so only the
// phase test of every fragment that may follow them excludes `fall`.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @immediate {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "fall"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @fall(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.ref.store %one to %clk : !bit, !ref
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^low
    }
    // CHECK-LABEL: simulation.design @immediate
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_1_0
    // CHECK: simulation.suspend.edge posedge
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: simulation.ref.store
    // CHECK: }
    // REPORT: talos clocked kernel class 0: once per slot
    // REPORT: talos clocked kernel: __talos_clocked_0_1_0 members=1 eligible=1 retained=0 snapshots=0 deferred=0
    // REPORT-NEXT: talos clocked kernel: __talos_clocked_0_2_0 members=1 eligible=1 retained=0 snapshots=0 deferred=0
    // REPORT-NOT: rejection
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @fall(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %q : !ref -> !bit
      %old = simulation.ref.load %r : !ref -> !bit
      %next = simulation.logic.binary xor %v, %old : !bit
      simulation.nba.enqueue %next to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// The negedge of `~clk` is the class's posedge, the kernel's own edge. The
// reader also reads `clk`, so it stays a process of its own that may run
// after the posedge kernel in its slot, and `q` keeps its NBA.

!bit = !simulation.logic<1>
!byte = !simulation.logic<8>
!byteref = !simulation.ref<!byte>
module attributes {native.debug_timing} {
  simulation.design @complemented_same_edge {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : !byte design
    simulation.storage.decl 2 in 0 : !byte design
    simulation.net.decl 0 in 0 : !bit design
    simulation.net.decl 1 in 0 : !bit design
    simulation.driver.decl 0 in 0 drives 0 : !bit design
    simulation.driver.decl 1 in 0 drives 1 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 port_input hierarchy "port"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "invert"
    simulation.code_unit.decl 5 in 0 always_ff hierarchy "count"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "reader"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %net1 = simulation.context.net %ctx[1] : !simulation.net<!bit>
      %q = simulation.context.storage %ctx[1] : !byteref
      %r = simulation.context.storage %ctx[2] : !byteref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<i1> -> !simulation.process
      %p1 = simulation.spawn @port(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @invert(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @count(%ctx, %clk, %q) : !simulation.context, !simulation.ref<i1>, !byteref -> !simulation.process
      %p4 = simulation.spawn @reader(%ctx, %net1, %clk, %q, %r) : !simulation.context, !simulation.net<!bit>, !simulation.ref<i1>, !byteref, !byteref -> !simulation.process
      simulation.return
    }
    simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.ref<i1> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      %five = simulation.time.constant 5
      %true = arith.constant true
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %five to ^toggle
    ^toggle:
      %v = simulation.ref.load %clk : !simulation.ref<i1> -> i1
      %t = arith.xori %v, %true : i1
      simulation.ref.store %t to %clk : i1, !simulation.ref<i1>
      cf.br ^wait
    }
    simulation.func private @port(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 9 : i32, code_unit_id = 3 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!bit>
      cf.br ^copy
    ^copy:
      %v = simulation.ref.load %clk : !simulation.ref<i1> -> i1
      %logic = simulation.logic.from_bits %v : i1 -> !bit
      simulation.driver.drive %driver = %logic : !simulation.driver<!bit>, !bit
      simulation.suspend.change %clk to ^copy : !simulation.ref<i1>
    }
    simulation.func private @invert(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
      %net = simulation.context.net %ctx[0] : !simulation.net<!bit>
      %driver = simulation.context.driver %ctx[1] : !simulation.driver<!bit>
      cf.br ^copy
    ^copy:
      %v = simulation.net.read %net : !simulation.net<!bit> -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      simulation.driver.drive %driver = %n : !simulation.driver<!bit>, !bit
      simulation.suspend.change %net to ^copy : !simulation.net<!bit>
    }
    // CHECK-LABEL: simulation.design @complemented_same_edge
    // CHECK-LABEL: simulation.func private @count
    // CHECK: simulation.nba.enqueue
    // REPORT: talos clocked kernel class 0: once per slot
    // REPORT: talos clocked kernel rejection: root accessed by event activation = 1
    simulation.func private @count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.ref<i1> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !byte
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.ref<i1>
    ^body:
      %old = simulation.ref.load %q : !byteref -> !byte
      %next = simulation.logic.binary add %old, %one : !byte
      simulation.nba.enqueue %next to %q : (!byte, !byteref) -> ()
      cf.br ^wait
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %net: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %clk: !simulation.ref<i1> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %net to ^body : !simulation.net<!bit>
    ^body:
      %c = simulation.ref.load %clk : !simulation.ref<i1> -> i1
      %v = simulation.ref.load %q : !byteref -> !byte
      %zero = simulation.logic.constant 0 : i8, 0 : i8 : !byte
      %w = arith.select %c, %v, %zero : !byte
      simulation.nba.enqueue %w to %r : (!byte, !byteref) -> ()
      cf.br ^wait
    }
  }
}
