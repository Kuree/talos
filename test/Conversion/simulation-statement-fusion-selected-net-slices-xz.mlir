// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{explain=true},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t 2>&1 | FileCheck %s --check-prefix=PLAN
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements,talos-sim-materialize-compute-fusion,simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=LLVM < %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// Four-state payloads include mixed X/Z on one arm and all Z on the other.
// Case equality verifies both planes, including after an unselected update.
// A selected packed-net view retains a nonzero-offset handle projection after
// branch canonicalization. Lower all certified leaves without a runtime load.
// Integer conditionals can canonicalize to a select between net handles.
// Both resolved nets and the selector are dependencies of that read. Retain
// the request -> transform -> response order, including when the net and
// output storage have the same descriptor number.
// PLAN: 1 plans (1 data-dependence order)
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK-NOT: simulation.spawn @producer_and_consumer
// CHECK-NOT: simulation.spawn @transform
// CHECK: simulation.func private @__talos_region_kernel_0_0
// CHECK: simulation.driver.drive
// CHECK: arith.select {{.*}} : !simulation.net<
// CHECK: simulation.net.extract
// CHECK: simulation.net.read
// CHECK: simulation.driver.drive
// CHECK: simulation.ref.store
// A select of known net handles must become a select of loaded values in the
// hot body, without passing through the arbitrary-handle runtime ABI.
// LLVM-LABEL: llvm.func @__talos_region_kernel_0_0.__talos_eval_body_0(
// LLVM-NOT: llvm.call @talos_rt_v1_native_state_load_plane
// LLVM: llvm.select {{.*}} : i1, i8
// LLVM-NOT: llvm.call @talos_rt_v1_native_state_load_plane
// LLVM-NOT: llvm.call @talos_rt_v1_native_handle_offset
// LLVM: llvm.return
// OUTPUT-NOT: FAIL
// OUTPUT: SELECTED NET SLICES XZ PASS
// OUTPUT-NOT: FAIL
!value = !simulation.logic<8>
!byte = !simulation.packed_array<8 : 0 x !simulation.logic<1>>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  schedule.native_scheduler = 3 : i32
} {
  simulation.design @selected_net_slices_xz {
    simulation.scope.decl 0
    simulation.scope.decl 1 parent 0
    simulation.storage.decl 0 in 0 : !value design
    simulation.storage.decl 1 in 0 : !value design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.net.decl 0 in 0 : !value design
    simulation.net.decl 1 in 0 : !byte design
    simulation.net.decl 2 in 0 : !byte design
    simulation.driver.decl 0 in 0 drives 0 : !value design
    simulation.driver.decl 1 in 0 drives 1 : !byte design
    simulation.driver.decl 2 in 0 drives 2 : !byte design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 1 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 4 in 0 initial hierarchy "stimulus"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 3 : i64} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %request = simulation.context.net %ctx[1] : !simulation.net<!byte>
      %alternate = simulation.context.net %ctx[2] : !simulation.net<!byte>
      %b = simulation.spawn @transform(%ctx, %request, %alternate) : !simulation.context, !simulation.net<!byte>, !simulation.net<!byte> -> !simulation.process
      %s = simulation.spawn @stimulus(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      %request = simulation.context.driver %ctx[1] : !simulation.driver<!byte>
      %response = simulation.context.net %ctx[0] : !simulation.net<!value>
      %out = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      cf.br ^body
    ^body:
      %r = simulation.net.read %response : !simulation.net<!value> -> !value
      simulation.ref.store %r to %out : !value, !simulation.ref<!value>
      %v = simulation.ref.load %input : !simulation.ref<!value> -> !value
      %low = simulation.logic.constant false, false : !simulation.logic<1>
      %wide = simulation.logic.concat %v, %low : (!value, !simulation.logic<1>) -> !simulation.logic<9>
      %packed = simulation.packed.unflatten %wide : (!simulation.logic<9>) -> !byte
      simulation.driver.drive %request = %packed : !simulation.driver<!byte>, !byte
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !simulation.ref<!value>, !simulation.net<!value>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %request: !simulation.net<!byte> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %alternate: !simulation.net<!byte> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %choose = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %response = simulation.context.driver %ctx[0] : !simulation.driver<!value>
      cf.br ^body
    ^body:
      %c = simulation.ref.load %choose : !simulation.ref<i1> -> i1
      cf.cond_br %c, ^left, ^right
    ^left:
      %sa = simulation.net.extract %request from 1 : !simulation.net<!byte> -> !simulation.net<!value>
      %a = simulation.net.read %sa : !simulation.net<!value> -> !value
      cf.br ^join(%a : !value)
    ^right:
      %sb = simulation.net.extract %alternate from 1 : !simulation.net<!byte> -> !simulation.net<!value>
      %b = simulation.net.read %sb : !simulation.net<!value> -> !value
      cf.br ^join(%b : !value)
    ^join(%value: !value):
      simulation.driver.drive %response = %value : !simulation.driver<!value>, !value
      simulation.suspend.any %request, %alternate, %choose edges [0, 0, 0] to ^body : !simulation.net<!byte>, !simulation.net<!byte>, !simulation.ref<i1>
    }
    // Exercise both select arms, a changed unselected input, and switching
    // back after that change. Positive delays let each activation settle.
    simulation.func @stimulus(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %input = simulation.context.storage %ctx[1] : !simulation.ref<!value>
      %choose = simulation.context.storage %ctx[2] : !simulation.ref<i1>
      %out = simulation.context.storage %ctx[0] : !simulation.ref<!value>
      %alternate = simulation.context.driver %ctx[2] : !simulation.driver<!byte>
      %a = simulation.logic.constant 17 : i8, 0 : i8 : !value
      %b = simulation.logic.constant 42 : i8, -1 : i8 : !value
      %next = simulation.logic.constant -1 : i8, -1 : i8 : !value
      %true = arith.constant true
      %false = arith.constant false
      %one = simulation.time.constant 1
      %low = simulation.logic.constant false, false : !simulation.logic<1>
      %wide_b = simulation.logic.concat %b, %low : (!value, !simulation.logic<1>) -> !simulation.logic<9>
      %packed_b = simulation.packed.unflatten %wide_b : (!simulation.logic<9>) -> !byte
      simulation.driver.drive %alternate = %packed_b : !simulation.driver<!byte>, !byte
      simulation.ref.store %a to %input : !value, !simulation.ref<!value>
      simulation.ref.store %true to %choose : i1, !simulation.ref<i1>
      simulation.suspend.delay %one to ^check_a
    ^check_a:
      %first = simulation.ref.load %out : !simulation.ref<!value> -> !value
      %first_ok = simulation.logic.compare case_eq %first, %a : (!value, !value) -> i1
      cf.cond_br %first_ok, ^select_b, ^fail
    ^select_b:
      simulation.ref.store %false to %choose : i1, !simulation.ref<i1>
      simulation.suspend.delay %one to ^check_b
    ^check_b:
      %second = simulation.ref.load %out : !simulation.ref<!value> -> !value
      %second_ok = simulation.logic.compare case_eq %second, %b : (!value, !value) -> i1
      cf.cond_br %second_ok, ^update_a, ^fail
    ^update_a:
      simulation.ref.store %next to %input : !value, !simulation.ref<!value>
      simulation.suspend.delay %one to ^check_unchanged
    ^check_unchanged:
      %third = simulation.ref.load %out : !simulation.ref<!value> -> !value
      %third_ok = simulation.logic.compare case_eq %third, %b : (!value, !value) -> i1
      cf.cond_br %third_ok, ^select_a, ^fail
    ^select_a:
      simulation.ref.store %true to %choose : i1, !simulation.ref<i1>
      simulation.suspend.delay %one to ^check_next
    ^check_next:
      %fourth = simulation.ref.load %out : !simulation.ref<!value> -> !value
      %fourth_ok = simulation.logic.compare case_eq %fourth, %next : (!value, !value) -> i1
      cf.cond_br %fourth_ok, ^pass, ^fail
    ^pass:
      %pass_text = simulation.bytes.constant "SELECTED NET SLICES XZ PASS"
      %pass_stdout = arith.constant 1 : i32
      simulation.display %ctx to %pass_stdout(%pass_text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^fail:
      %fail_text = simulation.bytes.constant "SELECTED NET SLICES XZ FAIL"
      %fail_stdout = arith.constant 1 : i32
      simulation.display %ctx to %fail_stdout(%fail_text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    }
  }
}
