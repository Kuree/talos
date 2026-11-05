// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true}))' -o %t.mlir 2> %t.log
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REPORT < %t.log

// The time-zero slot of a clock class (IEEE 1800-2023 9.4.2, Table 9-2). When
// only static initialization writes its sources (6.8), the sources keep their
// values and every copy chain root that starts at x or z moves only through x
// to the source's value or its complement (4.9.1, 10.3.2, 11.4.8), so all
// edges of that slot share one direction relative to the class and the
// opposite-edge members never run with a kernel there either ("once per
// slot"). Otherwise only later slots are excluded ("once per later slot").

// A second periodic process pulses the clock at time zero only. The class
// still changes once per later slot, but the time-zero slot holds both edges,
// so `fall` may follow the posedge kernel there and `q` keeps its NBA.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @time_zero {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "fall"
    simulation.code_unit.decl 5 in 0 initial hierarchy "pulse"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @fall(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @pulse(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
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
    simulation.func @pulse(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %delay = simulation.time.constant 1000
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      simulation.ref.store %one to %clk : !bit, !ref
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^idle
    ^idle:
      simulation.suspend.delay %delay to ^idle
    }
    // CHECK-LABEL: simulation.design @time_zero
    // CHECK-LABEL: simulation.func private @rise
    // CHECK: simulation.nba.enqueue
    // REPORT: talos clocked kernel class 0: once per later slot
    // REPORT: talos clocked kernel: __talos_clocked_0_2_0 members=1 eligible=1
    // REPORT-NEXT: talos clocked kernel rejection: root accessed by event activation = 1
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

// A complemented net copy swaps the edges relative to the class: `reader`
// waits on the posedge of `~clk`, the class's negedge, so it never shares a
// later slot with the posedge kernel that updates `q` (23.3.3, 10.3.2). At
// time zero the nets move once from z (through x for `~clk`) to the values
// of the quiet clock and its complement (4.9.1): `clk` is 0, so that slot
// holds only class negedges and the kernel, clocked through the port net, does
// not run there either.

!bit = !simulation.logic<1>
!byte = !simulation.logic<8>
!byteref = !simulation.ref<!byte>
module attributes {native.debug_timing} {
  simulation.design @complemented {
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
      %net0 = simulation.context.net %ctx[0] : !simulation.net<!bit>
      %p3 = simulation.spawn @count(%ctx, %net0, %q) : !simulation.context, !simulation.net<!bit>, !byteref -> !simulation.process
      %p4 = simulation.spawn @reader(%ctx, %net1, %q, %r) : !simulation.context, !simulation.net<!bit>, !byteref, !byteref -> !simulation.process
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
    // CHECK-LABEL: simulation.design @complemented
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_1_0
    // CHECK: simulation.suspend.edge posedge
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: simulation.ref.store
    // CHECK: }
    // REPORT: talos clocked kernel class 0: once per slot
    // REPORT: talos clocked kernel: __talos_clocked_0_1_0 members=1 eligible=1 retained=0 snapshots=0 deferred=0
    // REPORT-NOT: rejection: root accessed by event activation
    simulation.func private @count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !byte
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.net<!bit>
    ^body:
      %old = simulation.ref.load %q : !byteref -> !byte
      %next = simulation.logic.binary add %old, %one : !byte
      simulation.nba.enqueue %next to %q : (!byte, !byteref) -> ()
      cf.br ^wait
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.net<!bit>
    ^body:
      %v = simulation.ref.load %q : !byteref -> !byte
      simulation.nba.enqueue %v to %r : (!byte, !byteref) -> ()
      cf.br ^wait
    }
  }
}
// -----


// As above, with a testbench reader of `q` after a delay: the immediate kernel
// refuses `q`, and the deferred kernel stores it only because `reader` is
// excluded at time zero as well.

!bit = !simulation.logic<1>
!byte = !simulation.logic<8>
!byteref = !simulation.ref<!byte>
module attributes {native.debug_timing} {
  simulation.design @complemented_deferred {
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
    simulation.code_unit.decl 7 in 0 initial hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %net1 = simulation.context.net %ctx[1] : !simulation.net<!bit>
      %q = simulation.context.storage %ctx[1] : !byteref
      %r = simulation.context.storage %ctx[2] : !byteref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<i1> -> !simulation.process
      %p1 = simulation.spawn @port(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @invert(%ctx) : !simulation.context -> !simulation.process
      %net0 = simulation.context.net %ctx[0] : !simulation.net<!bit>
      %p3 = simulation.spawn @count(%ctx, %net0, %q) : !simulation.context, !simulation.net<!bit>, !byteref -> !simulation.process
      %p4 = simulation.spawn @reader(%ctx, %net1, %q, %r) : !simulation.context, !simulation.net<!bit>, !byteref, !byteref -> !simulation.process
      %p5 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
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
    // CHECK-LABEL: simulation.design @complemented_deferred
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_1_0
    // CHECK: simulation.suspend.edge posedge
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: simulation.ref.store
    // CHECK: }
    // REPORT: talos clocked kernel class 0: once per slot
    // REPORT: talos clocked kernel: __talos_clocked_0_1_0 members=1 eligible=1 retained=0 snapshots=0 deferred=1
    // REPORT-NOT: rejection: root accessed by event activation
    simulation.func private @count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !byte
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.net<!bit>
    ^body:
      %old = simulation.ref.load %q : !byteref -> !byte
      %next = simulation.logic.binary add %old, %one : !byte
      simulation.nba.enqueue %next to %q : (!byte, !byteref) -> ()
      cf.br ^wait
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.net<!bit>
    ^body:
      %v = simulation.ref.load %q : !byteref -> !byte
      simulation.nba.enqueue %v to %r : (!byte, !byteref) -> ()
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 1000
      simulation.suspend.delay %delay to ^done
    ^done:
      %q = simulation.context.storage %ctx[1] : !byteref
      %qv = simulation.ref.load %q : !byteref -> !byte
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "%h"
      simulation.display %ctx to %stdout(%format, %qv) newline = true radix = <hex> flags = [0, 0] : !simulation.bytes, !byte
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}

// -----

// `nclk = ~clk` is a 2-state variable, which starts at 0 rather than x (Table
// 6-7). At time zero the port net `c` may move from z to that stale 0 and
// then to 1 once the assignment has run: a class posedge and a class negedge in
// one slot. Only later slots are excluded, so `rise`, a class negedge member,
// may follow the kernel at time zero and `q` keeps its NBA.

!bit = !simulation.logic<1>
!byte = !simulation.logic<8>
!byteref = !simulation.ref<!byte>
module attributes {native.debug_timing} {
  simulation.design @stale {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : !byte design
    simulation.storage.decl 3 in 0 : !byte design
    simulation.net.decl 0 in 0 : !bit design
    simulation.driver.decl 0 in 0 drives 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 port_input hierarchy "port"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "invert"
    simulation.code_unit.decl 5 in 0 always_ff hierarchy "fall"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "rise"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %c = simulation.context.net %ctx[0] : !simulation.net<!bit>
      %q = simulation.context.storage %ctx[2] : !byteref
      %r = simulation.context.storage %ctx[3] : !byteref
      %p0 = simulation.spawn @port(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<i1> -> !simulation.process
      %p2 = simulation.spawn @invert(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @fall(%ctx, %c, %q) : !simulation.context, !simulation.net<!bit>, !byteref -> !simulation.process
      %p4 = simulation.spawn @rise(%ctx, %c, %q, %r) : !simulation.context, !simulation.net<!bit>, !byteref, !byteref -> !simulation.process
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
    simulation.func private @invert(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %nclk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %true = arith.constant true
      cf.br ^copy
    ^copy:
      %v = simulation.ref.load %clk : !simulation.ref<i1> -> i1
      %n = arith.xori %v, %true : i1
      simulation.ref.store %n to %nclk : i1, !simulation.ref<i1>
      simulation.suspend.change %clk to ^copy : !simulation.ref<i1>
    }
    simulation.func private @port(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 9 : i32, code_unit_id = 3 : i64} {
      %nclk = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!bit>
      cf.br ^copy
    ^copy:
      %v = simulation.ref.load %nclk : !simulation.ref<i1> -> i1
      %logic = simulation.logic.from_bits %v : i1 -> !bit
      simulation.driver.drive %driver = %logic : !simulation.driver<!bit>, !bit
      simulation.suspend.change %nclk to ^copy : !simulation.ref<i1>
    }
    // CHECK-LABEL: simulation.design @stale
    // CHECK-LABEL: simulation.func private @fall
    // CHECK: simulation.nba.enqueue
    // REPORT: talos clocked kernel class 0: once per later slot
    // REPORT: talos clocked kernel rejection: root accessed by event activation = 1
    simulation.func private @fall(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %c: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !byte
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %c to ^body : !simulation.net<!bit>
    ^body:
      %old = simulation.ref.load %q : !byteref -> !byte
      %next = simulation.logic.binary add %old, %one : !byte
      simulation.nba.enqueue %next to %q : (!byte, !byteref) -> ()
      cf.br ^wait
    }
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %c: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %r: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %c to ^body : !simulation.net<!bit>
    ^body:
      %v = simulation.ref.load %q : !byteref -> !byte
      simulation.nba.enqueue %v to %r : (!byte, !byteref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// `clk` is statically initialized to 1 (6.8): at time zero the port net moves
// from z to 1, a posedge, so the kernel clocked through it runs there, and
// `~clk` moves from z through x to 0, a class posedge too. `reader`, a class
// negedge member, runs in no slot with the kernel, and `q` is stored directly.

!bit = !simulation.logic<1>
!byte = !simulation.logic<8>
!byteref = !simulation.ref<!byte>
module attributes {native.debug_timing} {
  simulation.design @initialized {
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
      %net0 = simulation.context.net %ctx[0] : !simulation.net<!bit>
      %net1 = simulation.context.net %ctx[1] : !simulation.net<!bit>
      %q = simulation.context.storage %ctx[1] : !byteref
      %r = simulation.context.storage %ctx[2] : !byteref
      %true = arith.constant true
      simulation.ref.store %true to %clk : i1, !simulation.ref<i1>
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<i1> -> !simulation.process
      %p1 = simulation.spawn @port(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @invert(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @count(%ctx, %net0, %q) : !simulation.context, !simulation.net<!bit>, !byteref -> !simulation.process
      %p4 = simulation.spawn @reader(%ctx, %net1, %q, %r) : !simulation.context, !simulation.net<!bit>, !byteref, !byteref -> !simulation.process
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
    // CHECK-LABEL: simulation.design @initialized
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_
    // CHECK: simulation.suspend.edge posedge
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: simulation.ref.store
    // CHECK: }
    // REPORT: talos clocked kernel class 0: once per slot
    // REPORT-NOT: rejection: root accessed by event activation
    simulation.func private @count(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !byte
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.net<!bit>
    ^body:
      %old = simulation.ref.load %q : !byteref -> !byte
      %next = simulation.logic.binary add %old, %one : !byte
      simulation.nba.enqueue %next to %q : (!byte, !byteref) -> ()
      cf.br ^wait
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.net<!bit> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %q: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !byteref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !simulation.net<!bit>
    ^body:
      %v = simulation.ref.load %q : !byteref -> !byte
      simulation.nba.enqueue %v to %r : (!byte, !byteref) -> ()
      cf.br ^wait
    }
  }
}
