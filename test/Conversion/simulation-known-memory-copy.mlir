// RUN: talos-opt %s --talos-sim-build-compute-graph='vpi=off' --talos-sim-specialize-static-state-nba --convert-talos-sim-processes-to-llvm-coroutines -o %t.mlir
// RUN: FileCheck %s --check-prefix=LOWER < %t.mlir
// RUN: talos-translate --mlir-to-llvmir %t.mlir | %llvm_dist/bin/opt -S -passes='default<O3>,verify' | FileCheck %s

// IEEE 1800-2023 6.3.1/4.6: when the executing path proves both the read and
// old destination known, a memory-backed copy leaves the unknown plane alone.
// Do not materialize a temporary zero unknown buffer before optimization;
// nothing reads or writes the unknown plane, so its unused address is gone
// before LLVM export.
// A known RHS alone must still clear an unproved destination's old X/Z bits;
// an entirely unproved copy retains both planes.
// LOWER-LABEL: llvm.func @known(
// LOWER-NOT: llvm.intr.memset
// LOWER-NOT: @__talos_state_unknown
// LOWER: llvm.return
// LOWER-LABEL: llvm.func @known_dynamic(
// LOWER-NOT: @__talos_state_unknown
// LOWER: llvm.return
// LOWER-LABEL: llvm.func @known_rhs(
// LOWER: llvm.intr.memset
// LOWER: llvm.return

// CHECK-LABEL: define void @known(
// CHECK-NOT: @__talos_state_unknown
// CHECK-NOT: @llvm.memset
// CHECK: ret void
// CHECK-LABEL: define void @known_dynamic(
// CHECK-NOT: @__talos_state_unknown
// CHECK: ret void
// CHECK-LABEL: define void @known_rhs(
// CHECK: @__talos_state_unknown
// CHECK: @llvm.memset
// CHECK: ret void
// CHECK-LABEL: define void @canonical(
// CHECK: @__talos_state_unknown
// CHECK: ret void

// The dynamic negatives reach the same fused bulk-copy lowering as the
// positive case. Neither a known RHS alone nor an unproved copy can elide
// the destination's unknown-plane publication (LRM 6.3.1/9.4.2).
// LOWER-LABEL: llvm.func @known_rhs_dynamic(
// LOWER: @__talos_state_unknown
// LOWER-COUNT-2: llvm.call @talos_rt_v1_native_state_store_plane
// LOWER: llvm.return
// LOWER-LABEL: llvm.func @canonical_dynamic(
// LOWER: @__talos_state_unknown
// LOWER-COUNT-2: llvm.call @talos_rt_v1_native_state_store_plane
// LOWER: llvm.return
// CHECK-LABEL: define void @known_rhs_dynamic(
// CHECK: @__talos_state_unknown
// CHECK-COUNT-2: call i32 @talos_rt_v1_native_state_store_plane
// CHECK: ret void
// CHECK-LABEL: define void @canonical_dynamic(
// CHECK: @__talos_state_unknown
// CHECK-COUNT-2: call i32 @talos_rt_v1_native_state_store_plane
// CHECK: ret void

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @known_copy {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<256> design
    simulation.storage.decl 1 in 0 : !simulation.logic<256> design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.known"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.canonical"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.known_rhs"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.known_dynamic"
    simulation.code_unit.decl 5 in 0 function hierarchy "top.known_rhs_dynamic"
    simulation.code_unit.decl 6 in 0 function hierarchy "top.canonical_dynamic"
    simulation.func @known(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %src = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<256>>
      %dst = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src {schedule.native.known_read} : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst {schedule.native.known_store} : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return
    }
    simulation.func @known_dynamic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                    %dst: !simulation.ref<!simulation.logic<256>> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %src = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src {schedule.native.known_read} : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst {schedule.native.known_store} : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return
    }
    simulation.func @known_rhs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %src = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<256>>
      %dst = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src {schedule.native.known_read} : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return
    }
    simulation.func @canonical(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %src = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<256>>
      %dst = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return
    }
    simulation.func @known_rhs_dynamic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                         %dst: !simulation.ref<!simulation.logic<256>> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %src = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src {schedule.native.known_read} : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return
    }
    simulation.func @canonical_dynamic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                         %dst: !simulation.ref<!simulation.logic<256>> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %src = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return
    }
  }
}
