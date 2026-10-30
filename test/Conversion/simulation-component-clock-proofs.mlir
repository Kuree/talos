// RUN: talos-opt %s --test-talos-clock-inference -o /dev/null 2>&1 | FileCheck %s --check-prefix=FACTS
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion),test-talos-clock-inference)' -o %t.mlir 2> %t.facts
// RUN: FileCheck %s --check-prefix=FACTS < %t.facts
// RUN: FileCheck %s --check-prefix=OWNERS < %t.mlir

// Component fusion must retain the periodic/tick-bound certificates needed by
// native NBA latches. Protect the entire scalar transport path, including a
// complement and an arbitrary always executor boundary. An unrelated DAG must
// still fuse, so retaining these facts cannot mean disabling component fusion.
// FACTS: clock 0: periodic domain=1:0 half-period=5
// FACTS: clock 1: tick-driven domain=1:0 half-period=5
// FACTS: net 0: periodic domain=1:0 half-period=5 origin=1:0{{$}}
// FACTS-NEXT: net 1: periodic domain=1:0 half-period=5 inverted origin=1:0 complement{{$}}
// FACTS-NEXT: net 2: periodic domain=1:0 half-period=5 inverted origin=1:0 complement{{$}}
// FACTS-NEXT: net 3: periodic domain=1:0 half-period=5 origin=1:0{{$}}
// OWNERS: simulation.spawn @port
// OWNERS: simulation.spawn @invert
// OWNERS: simulation.spawn @boundary
// OWNERS: simulation.spawn @invert_again
// OWNERS: simulation.spawn @edge
// OWNERS: simulation.spawn @__talos_region_kernel_0_0
// OWNERS-NOT: simulation.spawn @side_a
// OWNERS-NOT: simulation.spawn @side_b
// OWNERS: simulation.func private @__talos_region_kernel_0_0

!bit = !simulation.logic<1>
!net = !simulation.net<!bit>
!driver = !simulation.driver<!bit>
!ref = !simulation.ref<i1>
!word = !simulation.ref<i8>
!ctx = !simulation.context
module {
  simulation.design @clock_corridor {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.net.decl 0 in 0 : !bit design
    simulation.net.decl 1 in 0 : !bit design
    simulation.net.decl 2 in 0 : !bit design
    simulation.net.decl 3 in 0 : !bit design
    simulation.driver.decl 0 in 0 drives 0 : !bit design
    simulation.driver.decl 1 in 0 drives 1 : !bit design
    simulation.driver.decl 2 in 0 drives 2 : !bit design
    simulation.driver.decl 3 in 0 drives 3 : !bit design
    simulation.code_unit.decl 1 in 0 always hierarchy "source"
    simulation.code_unit.decl 2 in 0 port_input hierarchy "port"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "invert"
    simulation.code_unit.decl 4 in 0 always hierarchy "boundary"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "invert_again"
    simulation.code_unit.decl 6 in 0 always hierarchy "edge"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "side_a"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "side_b"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @source(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 1 : i64, entry_kind = 3 : i32, test.clock_storage = 0 : i64, test.clock_half_period = 5 : i64} {
      %clock = simulation.context.storage %ctx[0] : !ref
      cf.br ^tick
    ^tick:
      %v = simulation.ref.load %clock : !ref -> i1
      %one = arith.constant true
      %toggle = arith.xori %v, %one : i1
      simulation.ref.store %toggle to %clock : i1, !ref
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^tick
    }
    simulation.func @port(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 2 : i64, entry_kind = 9 : i32} {
      %clock = simulation.context.storage %ctx[0] : !ref
      %driver = simulation.context.driver %ctx[0] : !driver
      cf.br ^copy
    ^copy:
      %v = simulation.ref.load %clock : !ref -> i1
      %logic = simulation.logic.from_bits %v : i1 -> !bit
      simulation.driver.drive %driver = %logic : !driver, !bit
      simulation.suspend.change %clock to ^copy : !ref
    }
    simulation.func @invert(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 3 : i64, entry_kind = 7 : i32} {
      %net = simulation.context.net %ctx[0] : !net
      %driver = simulation.context.driver %ctx[1] : !driver
      cf.br ^copy
    ^copy:
      %v = simulation.net.read %net : !net -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      simulation.driver.drive %driver = %n : !driver, !bit
      simulation.suspend.change %net to ^copy : !net
    }
    simulation.func @boundary(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 4 : i64, entry_kind = 3 : i32} {
      %net = simulation.context.net %ctx[1] : !net
      %driver = simulation.context.driver %ctx[2] : !driver
      cf.br ^copy
    ^copy:
      %v = simulation.net.read %net : !net -> !bit
      simulation.driver.drive %driver = %v : !driver, !bit
      simulation.suspend.change %net to ^copy : !net
    }
    simulation.func @invert_again(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 5 : i64, entry_kind = 7 : i32} {
      %net = simulation.context.net %ctx[2] : !net
      %driver = simulation.context.driver %ctx[3] : !driver
      cf.br ^copy
    ^copy:
      %v = simulation.net.read %net : !net -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      simulation.driver.drive %driver = %n : !driver, !bit
      simulation.suspend.change %net to ^copy : !net
    }
    simulation.func @edge(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 6 : i64, entry_kind = 3 : i32} {
      %clock = simulation.context.net %ctx[3] : !net
      %out = simulation.context.storage %ctx[1] : !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clock to ^body : !net
    ^body:
      %one = arith.constant true
      simulation.ref.store %one to %out : i1, !ref
      cf.br ^wait
    }
    simulation.func @side_a(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 7 : i64, entry_kind = 4 : i32} {
      %in = simulation.context.storage %ctx[2] : !word
      %out = simulation.context.storage %ctx[3] : !word
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !word -> i8
      %one = arith.constant 1 : i8
      %n = arith.addi %v, %one : i8
      simulation.ref.store %n to %out : i8, !word
      simulation.suspend.change %in to ^body : !word
    }
    simulation.func @side_b(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 8 : i64, entry_kind = 4 : i32} {
      %in = simulation.context.storage %ctx[3] : !word
      %out = simulation.context.storage %ctx[4] : !word
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !word -> i8
      %one = arith.constant 1 : i8
      %n = arith.addi %v, %one : i8
      simulation.ref.store %n to %out : i8, !word
      simulation.suspend.change %in to ^body : !word
    }
    simulation.func @root(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 9 : i64, entry_kind = 0 : i32} {
      %a = simulation.spawn @source(%ctx) : !ctx -> !simulation.process
      %b = simulation.spawn @port(%ctx) : !ctx -> !simulation.process
      %c = simulation.spawn @invert(%ctx) : !ctx -> !simulation.process
      %d = simulation.spawn @boundary(%ctx) : !ctx -> !simulation.process
      %e = simulation.spawn @invert_again(%ctx) : !ctx -> !simulation.process
      %f = simulation.spawn @edge(%ctx) : !ctx -> !simulation.process
      %g = simulation.spawn @side_a(%ctx) : !ctx -> !simulation.process
      %h = simulation.spawn @side_b(%ctx) : !ctx -> !simulation.process
      simulation.return
    }
  }
}
