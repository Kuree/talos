// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s

// IEEE 1800-2023 21.2.3: the runtime compares a $monitor's arguments once per
// time slot only when re-evaluating them cannot change their value by itself.
// An argument observer the monitor's change wait binds that reads the time
// (or calls out, or draws a random number) carries TALOS_RT_OBSERVER_IMPURE
// (8) and keeps its subscriptions. Other observers (here an unbound one that
// also reads the time, as covergroup and power observers do) never carry the
// bit, so their exact-flag checks are unchanged.

module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @d {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design hierarchy "d.a" debug "a"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "d.root"
    simulation.code_unit.decl 2 in 0 fork hierarchy "d.monitor"
    simulation.code_unit.decl 3 in 0 observer hierarchy "d.pure"
    simulation.code_unit.decl 4 in 0 observer hierarchy "d.time"
    simulation.code_unit.decl 5 in 0 observer hierarchy "d.unbound_time"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %p = simulation.spawn @monitor(%ctx, %a) : !simulation.context, !simulation.ref<!simulation.logic<8>> -> !simulation.process
      simulation.monitor.register %p
      simulation.return
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %a: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
        attributes {code_unit_id = 2 : i64, domain = 0 : i32, entry_kind = 13 : i32, home_region = 16 : i32, simulation.persistent_monitor} {
      cf.br ^loop
    ^loop:
      %v = simulation.ref.load %a : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %t = simulation.time.now %ctx
      %pure = simulation.observer.bind @pure values(%a, %a : !simulation.ref<!simulation.logic<8>>, !simulation.ref<!simulation.logic<8>>) captures 1 : !simulation.observer<!simulation.logic<8>>
      %time = simulation.observer.bind @time values() captures 0 : !simulation.observer<i64>
      simulation.suspend.observe %pure, %time, %v, %t conditions 0 edges [0, 0] indices [-1, -1] to ^loop {resume_region = 16 : i32} : !simulation.observer<!simulation.logic<8>>, !simulation.observer<i64>, !simulation.logic<8>, i64
    }
    simulation.func private @pure(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %a: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) -> !simulation.logic<8>
        attributes {code_unit_id = 3 : i64, domain = 0 : i32, entry_kind = 14 : i32, home_region = 2 : i32, schedule.observer_four_state = true, schedule.observer_width = 8 : i32, simulation.observer_result = 1 : i32} {
      %v = simulation.ref.load %a : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.return %v : !simulation.logic<8>
    }
    simulation.func private @time(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i64
        attributes {code_unit_id = 4 : i64, domain = 0 : i32, entry_kind = 14 : i32, home_region = 2 : i32, schedule.observer_four_state = false, schedule.observer_width = 64 : i32, simulation.observer_result = 1 : i32} {
      %t = simulation.time.now %ctx
      simulation.return %t : i64
    }
    simulation.func private @unbound_time(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i64
        attributes {code_unit_id = 5 : i64, domain = 0 : i32, entry_kind = 14 : i32, home_region = 2 : i32, schedule.observer_four_state = false, schedule.observer_width = 64 : i32, simulation.observer_result = 1 : i32} {
      %t = simulation.time.now %ctx
      simulation.return %t : i64
    }
  }
}

// CHECK-LABEL: llvm.mlir.global internal constant @__talos_observers_v1
// CHECK: llvm.mlir.constant(3 : i64)
// CHECK: llvm.insertvalue {{.*}}[3]
// CHECK-NEXT: llvm.mlir.constant(1 : i32)
// CHECK-NEXT: llvm.insertvalue {{.*}}[4]
// CHECK: llvm.mlir.constant(4 : i64)
// CHECK: llvm.insertvalue {{.*}}[3]
// CHECK-NEXT: llvm.mlir.constant(8 : i32)
// CHECK-NEXT: llvm.insertvalue {{.*}}[4]
// CHECK: llvm.mlir.constant(5 : i64)
// CHECK: llvm.insertvalue {{.*}}[3]
// CHECK-NEXT: llvm.mlir.constant(0 : i32)
// CHECK-NEXT: llvm.insertvalue {{.*}}[4]
