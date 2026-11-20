// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=off}))' -o %t.disjoint 2> %t.disjoint.log
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.upper_input set={low_bit=0 : i64}},simulation.design(talos-sim-coalesce-continuous-drivers{vpi=off}))' -o %t.shared 2> %t.shared.log
// RUN: FileCheck %s --check-prefix=DISJOINT < %t.disjoint.log && FileCheck %s --check-prefix=SHARED < %t.shared.log
// RUN: FileCheck %s --check-prefix=SPLIT-IR < %t.disjoint && FileCheck %s --check-prefix=SHARED-IR < %t.shared

// A 256-bit bus is assembled from two continuous assignments. Disjoint
// 128-bit sources retain their independent wakes; slices of the same source
// share an activation. The two one-word lanes keep their shared wake.
// SPLIT-IR: simulation.spawn @word_low.coalesced(
// SPLIT-IR: simulation.spawn @low(
// SPLIT-IR: simulation.spawn @high(
// SHARED-IR: simulation.spawn @word_low.coalesced(
// SHARED-IR: simulation.spawn @low.coalesced(
// DISJOINT: talos coalesce-drivers: candidates=4 merged=2 runs=1
// SHARED: talos coalesce-drivers: candidates=4 merged=4 runs=2

!bus = !simulation.logic<256>
!lane = !simulation.logic<128>
!ref = !simulation.ref<!bus>
!view = !simulation.ref<!lane>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.closed_executable, native.debug_timing} {
 simulation.design @wide_sources {
  simulation.scope.decl 0
  simulation.storage.decl 0 in 0 : !bus design
  simulation.storage.decl 1 in 0 : !bus design
  simulation.storage.decl 2 in 0 : !lane design
  simulation.storage.decl 3 in 0 : !lane design
  simulation.code_unit.decl 5 in 0 continuous hierarchy "word_low"
  simulation.code_unit.decl 6 in 0 continuous hierarchy "word_high"
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
  simulation.code_unit.decl 4 in 0 initial hierarchy "drive"
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %src = simulation.context.storage %ctx[0] : !ref
    %dst = simulation.context.storage %ctx[1] : !ref
    %small_src = simulation.context.storage %ctx[2] : !view
    %small_dst = simulation.context.storage %ctx[3] : !view
    %wl = simulation.spawn @word_low(%ctx, %small_src, %small_dst) : !simulation.context, !view, !view -> !simulation.process
    %wh = simulation.spawn @word_high(%ctx, %small_src, %small_dst) : !simulation.context, !view, !view -> !simulation.process
    %stim = simulation.spawn @drive(%ctx, %src, %dst) : !simulation.context, !ref, !ref -> !simulation.process
    %lo = simulation.spawn @low(%ctx, %src, %dst) : !simulation.context, !ref, !ref -> !simulation.process
    %hi = simulation.spawn @high(%ctx, %src, %dst) : !simulation.context, !ref, !ref -> !simulation.process
    simulation.return
  }
  simulation.func private @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
    %low = simulation.ref.extract %src from 0 : !ref -> !view
    %high = simulation.ref.extract %src from 128 : !ref -> !view
    %a = simulation.ref.extract %dst from 0 : !ref -> !simulation.ref<!simulation.logic<2>>
    %b = simulation.ref.extract %dst from 128 : !ref -> !simulation.ref<!simulation.logic<2>>
    %zero = simulation.logic.constant 0 : i256, 0 : i256 : !bus
    simulation.ref.store %zero to %src : !bus, !ref
    %d = simulation.time.constant 1
    simulation.suspend.delay %d to ^low_change
  ^low_change:
    %one = simulation.logic.constant 1 : i128, 0 : i128 : !lane
    simulation.ref.store %one to %low : !lane, !view
    simulation.suspend.delay %d to ^high_change
  ^high_change:
    %first_a = simulation.ref.load %a : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
    %first_b = simulation.ref.load %b : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
    %fmt = simulation.bytes.constant "%b %b"
    %fd = arith.constant 1 : i32
    simulation.display %ctx to %fd(%fmt, %first_a, %first_b) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<2>, !simulation.logic<2>
    %xz = simulation.logic.constant 2 : i128, 1 : i128 : !lane
    simulation.ref.store %xz to %high : !lane, !view
    simulation.suspend.delay %d to ^done
  ^done:
    %last_a = simulation.ref.load %a : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
    %last_b = simulation.ref.load %b : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
    simulation.display %ctx to %fd(%fmt, %last_a, %last_b) newline = true radix = <binary> flags = [0, 0, 0] : !simulation.bytes, !simulation.logic<2>, !simulation.logic<2>
    %exit = arith.constant 0 : i32
    simulation.finish %ctx, %exit
    simulation.return
  }
  simulation.func private @word_low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !view {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %dst: !view {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
    cf.br ^work
  ^work:
    %input = simulation.ref.extract %src from 0 : !view -> !simulation.ref<!simulation.logic<64>>
    %output = simulation.ref.extract %dst from 0 : !view -> !simulation.ref<!simulation.logic<64>>
    %bits = simulation.ref.load %input : !simulation.ref<!simulation.logic<64>> -> !simulation.logic<64>
    simulation.ref.store %bits to %output {simulation.continuous_store} : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
    simulation.suspend.change %input to ^work : !simulation.ref<!simulation.logic<64>>
  }
  simulation.func private @word_high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !view {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %dst: !view {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
    cf.br ^work
  ^work:
    %input = simulation.ref.extract %src from 64 : !view -> !simulation.ref<!simulation.logic<64>>
    %output = simulation.ref.extract %dst from 64 : !view -> !simulation.ref<!simulation.logic<64>>
    %bits = simulation.ref.load %input : !simulation.ref<!simulation.logic<64>> -> !simulation.logic<64>
    simulation.ref.store %bits to %output {simulation.continuous_store} : !simulation.logic<64>, !simulation.ref<!simulation.logic<64>>
    simulation.suspend.change %input to ^work : !simulation.ref<!simulation.logic<64>>
  }
  simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^work
  ^work:
    %input = simulation.ref.extract %src from 0 : !ref -> !view
    %output = simulation.ref.extract %dst from 0 : !ref -> !view
    %bits = simulation.ref.load %input : !view -> !lane
    simulation.ref.store %bits to %output {simulation.continuous_store} : !lane, !view
    simulation.suspend.change %input to ^work : !view
  }
  simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^work
  ^work:
    %input = simulation.ref.extract %src from 128 {test.upper_input} : !ref -> !view
    %output = simulation.ref.extract %dst from 128 : !ref -> !view
    %bits = simulation.ref.load %input : !view -> !lane
    simulation.ref.store %bits to %output {simulation.continuous_store} : !lane, !view
    simulation.suspend.change %input to ^work : !view
  }
 }
}
