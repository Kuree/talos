// RUN: talos-opt %s --talos-sim-materialize-dpi-exports --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s

// An exported task's output formal is an automatic variable of its
// activation (IEEE 1800-2023 35.8: exported tasks follow exported functions);
// the export thunk copies it to the foreign caller's argument when the task
// returns, the copy-out of an output argument. The thunk reads each
// plane of the 65-bit four-state formal through its stable handle into the
// caller's buffer: the read of no design state, value plane then unknown
// plane, a bit outside the variable reading 0. Each read's status merges
// into the thunk's: the first failure is kept.
!out = !simulation.logic<65>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  dpi.has_exports
} {
  simulation.design @exports {
    simulation.scope.decl 0 hierarchy "exports"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "exports.root"
    simulation.code_unit.decl 2 in 0 task hierarchy "exports.work" {
      dpi.abi_signature = [
        #dpi.abi<kind = logic_vector, direction = output, width = 65, fourState = true, isSigned = false>,
        #dpi.abi<kind = logic_vector, direction = output, width = 65, fourState = true, isSigned = false>
      ],
      dpi.aggregate_layouts = [unit, unit],
      dpi.c_identifier = "c_work",
      dpi.export,
      dpi.export_id = 7 : i32,
      dpi.logical_inputs = 1 : i32,
      dpi.scope_id = 0 : i64
    }
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      simulation.return
    }
    simulation.func @work(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %result: !simulation.ref<!out> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 12 : i32,
          dpi.abi_signature = [
            #dpi.abi<kind = logic_vector, direction = output, width = 65, fourState = true, isSigned = false>,
            #dpi.abi<kind = logic_vector, direction = output, width = 65, fourState = true, isSigned = false>
          ],
          dpi.aggregate_layouts = [unit, unit],
          dpi.c_identifier = "c_work",
          dpi.elided_inputs = array<i64: 0>,
          dpi.export,
          dpi.export_id = 7 : i32,
          dpi.logical_inputs = 1 : i32,
          dpi.scope_id = 0 : i64} {
      %value = simulation.logic.constant 1 : i65, 0 : i65 : !out
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^write {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^write:
      simulation.ref.store %value to %result : !out, !simulation.ref<!out>
      simulation.return
    }
  }
}

// CHECK-LABEL: llvm.func @work.__talos_dpi_export_bridge.__talos_dpi_export(
// CHECK-SAME: %[[CONTEXT:[^:]*]]: !llvm.ptr, %{{[^:]*}}: !llvm.ptr, %{{[^:]*}}: i32, %[[OUTPUTS:[^:]*]]: !llvm.ptr, %{{[^:]*}}: i32)
// CHECK: llvm.alloca %{{[0-9]+}} x i64 {alignment = 8 : i64}
// CHECK-NEXT: %{{[0-9]+}} = llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[HANDLE_SLOT:[0-9]+]] = llvm.alloca %{{[0-9]+}} x i64 {alignment = 8 : i64}
// CHECK-NEXT: %{{[0-9]+}} = llvm.mlir.constant(1 : i64) : i64
// CHECK-NEXT: %[[STATUS:[0-9]+]] = llvm.alloca %{{[0-9]+}} x i32 {alignment = 4 : i64}
// CHECK: llvm.call @talos_rt_v1_native_state_alloc(
// CHECK: llvm.return
// CHECK-NEXT: ^[[COPY:bb[0-9]+]]:
// CHECK-NEXT: %[[HANDLE:[0-9]+]] = llvm.load %[[HANDLE_SLOT]] {alignment = 8 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: %[[DESCRIPTOR:[0-9]+]] = llvm.getelementptr %[[OUTPUTS]][0]
// CHECK-NEXT: %[[VALUE_FIELD:[0-9]+]] = llvm.getelementptr %[[DESCRIPTOR]][0, 4]
// CHECK-NEXT: %[[VALUE:[0-9]+]] = llvm.load %[[VALUE_FIELD]] : !llvm.ptr -> !llvm.ptr
// CHECK-NEXT: %[[NO_STATE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[WIDTH:[0-9]+]] = llvm.mlir.constant(65 : i64) : i64
// CHECK-NEXT: %[[VALUE_PLANE:[0-9]+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[ZERO_FILL:[0-9]+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[VALUE_STATUS:[0-9]+]] = llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[VALUE]], %[[NO_STATE]], %[[HANDLE]], %[[WIDTH]], %[[VALUE_PLANE]], %[[ZERO_FILL]], %[[VALUE]])
// CHECK-NEXT: %[[CURRENT:[0-9]+]] = llvm.load %[[STATUS]] {alignment = 4 : i64} : !llvm.ptr -> i32
// CHECK-NEXT: %[[OK:[0-9]+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[FIRST:[0-9]+]] = llvm.icmp "eq" %[[CURRENT]], %[[OK]] : i32
// CHECK-NEXT: %[[MERGED:[0-9]+]] = llvm.select %[[FIRST]], %[[VALUE_STATUS]], %[[CURRENT]] : i1, i32
// CHECK-NEXT: llvm.store %[[MERGED]], %[[STATUS]] {alignment = 4 : i64} : i32, !llvm.ptr
// CHECK-NEXT: %[[UNKNOWN_DESCRIPTOR:[0-9]+]] = llvm.getelementptr %[[OUTPUTS]][0]
// CHECK-NEXT: %[[UNKNOWN_FIELD:[0-9]+]] = llvm.getelementptr %[[UNKNOWN_DESCRIPTOR]][0, 5]
// CHECK-NEXT: %[[UNKNOWN:[0-9]+]] = llvm.load %[[UNKNOWN_FIELD]] : !llvm.ptr -> !llvm.ptr
// CHECK-NEXT: %[[NO_STATE:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[WIDTH:[0-9]+]] = llvm.mlir.constant(65 : i64) : i64
// CHECK-NEXT: %[[UNKNOWN_PLANE:[0-9]+]] = llvm.mlir.constant(1 : i32) : i32
// CHECK-NEXT: %[[ZERO_FILL:[0-9]+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[UNKNOWN_STATUS:[0-9]+]] = llvm.call @talos_rt_v1_native_state_load_plane(%[[CONTEXT]], %[[UNKNOWN]], %[[NO_STATE]], %[[HANDLE]], %[[WIDTH]], %[[UNKNOWN_PLANE]], %[[ZERO_FILL]], %[[UNKNOWN]])
// CHECK-NEXT: %[[CURRENT:[0-9]+]] = llvm.load %[[STATUS]] {alignment = 4 : i64} : !llvm.ptr -> i32
// CHECK-NEXT: %[[OK:[0-9]+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[FIRST:[0-9]+]] = llvm.icmp "eq" %[[CURRENT]], %[[OK]] : i32
// CHECK-NEXT: %[[MERGED:[0-9]+]] = llvm.select %[[FIRST]], %[[UNKNOWN_STATUS]], %[[CURRENT]] : i1, i32
// CHECK-NEXT: llvm.store %[[MERGED]], %[[STATUS]] {alignment = 4 : i64} : i32, !llvm.ptr
// CHECK-NEXT: llvm.br
// The copy runs once the task has returned.
// CHECK: %[[TASK_STATUS:[0-9]+]] = llvm.call @talos_rt_v1_dpi_export_task_run(%[[CONTEXT]], %{{[0-9]+}})
// CHECK-NEXT: llvm.store %[[TASK_STATUS]], %[[STATUS]] {alignment = 4 : i64} : i32, !llvm.ptr
// CHECK-NEXT: %[[DONE:[0-9]+]] = llvm.mlir.constant(0 : i32) : i32
// CHECK-NEXT: %[[RETURNED:[0-9]+]] = llvm.icmp "eq" %[[TASK_STATUS]], %[[DONE]] : i32
// CHECK-NEXT: llvm.cond_br %[[RETURNED]], ^[[COPY]], ^{{bb[0-9]+}}
