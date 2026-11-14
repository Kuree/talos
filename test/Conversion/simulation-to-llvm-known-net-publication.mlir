// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=full},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s --check-prefix=OFF

// A known-store certificate is produced only behind resolved-net guards;
// those guards are exercised in simulation-known-net-range-runtime.mlir.
// Here lower that certificate on an exclusive sparse contribution. Writable
// VPI can decouple a deposited/forced net from canonical driver state (LRM
// 38.34, 10.6.2), so ORIGINAL-layout guarded handles must keep both planes.
// A temporary clean copy must not silently strengthen this certificate.
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  schedule.native_scheduler = 2 : i32
} {
  simulation.design @known_net_publication {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "known_net_publication.read"
    simulation.code_unit.decl 2 in 0 function hierarchy "known_net_publication.drive"
    simulation.code_unit.decl 3 in 0 root_initializer hierarchy "known_net_publication.root"
    simulation.code_unit.decl 4 in 0 initial hierarchy "known_net_publication.initial"
    simulation.net.decl 0 in 0 : !simulation.logic<32> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<32> design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 3 : i64} {
      %process = simulation.spawn @initial(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @initial(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i32, 0 : i32 : !simulation.logic<32>
      // Establish the hand-authored certificate's old-net precondition.
      %raw = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<32>>
      %high = simulation.driver.extract %raw from 24 : !simulation.driver<!simulation.logic<32>> -> !simulation.driver<!simulation.logic<8>>
      %zero8 = simulation.logic.constant 0 : i8, 0 : i8 : !simulation.logic<8>
      simulation.driver.drive %high = %zero8 : !simulation.driver<!simulation.logic<8>>, !simulation.logic<8>
      simulation.call @drive_net(%ctx, %zero) : (!simulation.context, !simulation.logic<32>) -> ()
      %value = simulation.call @read_net(%ctx) : (!simulation.context) -> !simulation.logic<32>
      simulation.return
    }
    simulation.func @read_net(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        -> !simulation.logic<32>
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %net = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<32>>
      %value = simulation.net.read %net : !simulation.net<!simulation.logic<32>> -> !simulation.logic<32>
      simulation.return %value : !simulation.logic<32>
    }
    simulation.func @drive_net(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %value: !simulation.logic<32> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %driver = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<32>>
      %view = simulation.driver.extract %driver from 24 : !simulation.driver<!simulation.logic<32>> -> !simulation.driver<!simulation.logic<8>>
      %known = simulation.logic.constant 7 : i8, 0 : i8 : !simulation.logic<8>
      simulation.driver.drive %view = %known {schedule.native.known_store} : !simulation.driver<!simulation.logic<8>>, !simulation.logic<8>
      simulation.return
    }
  }
}

// CHECK-LABEL: llvm.func @drive_net(
// CHECK: llvm.mlir.addressof @__talos_state_unknown
// CHECK: llvm.call @talos_rt_v1_native_state_store_plane
// CHECK: llvm.return

// OFF-LABEL: llvm.func @drive_net(
// The raw high byte is at plane byte 7; the resolved net high byte is at 3.
// Only the raw unknown plane is accessed. No resolved-net U load/store remains.
// OFF: %[[RAW_U:.*]] = llvm.mlir.addressof @__talos_state_unknown
// OFF: %[[RAW_PTR:.*]] = llvm.getelementptr %[[RAW_U]][7]
// OFF: llvm.store %{{.*}}, %[[RAW_PTR]]
// OFF-NOT: llvm.mlir.addressof @__talos_state_unknown
// OFF-NOT: llvm.getelementptr %[[RAW_U]]
// OFF-NOT: llvm.call @talos_rt_v1_native_state_store_plane
// OFF: llvm.return
