// RUN: talos-opt %s --talos-sim-thread-runtime-statuses | FileCheck %s --check-prefix=STATUS
// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=NATIVE

// A failed registration of the activation's managed root range leaves no
// range to unregister: the failure exit of its status check (root_range_push)
// returns without a pop, while the failure exit of every other check pops the
// range. Each lowering of status checks keeps that: status threading of
// functions, plain processes and coroutine ramps.

// STATUS-LABEL: simulation.func private @fn(
// STATUS: %[[RECORD:.*]] = llvm.alloca %{{.*}} x !llvm.struct<(ptr, i64, ptr, i64)>
// STATUS: %[[PUSHED:.*]] = schedule.gc.root_range.push %[[RECORD]]
// STATUS-NEXT: %[[PUSH_STATUS:.*]] = runtime.status.from_bits %[[PUSHED]]
// STATUS-NEXT: %[[PUSH_OK:.*]] = runtime.status.is %[[PUSH_STATUS]], <ok>
// STATUS-NEXT: cf.cond_br %[[PUSH_OK]], ^{{bb[0-9]+}}, ^[[PUSH_FAILED:bb[0-9]+]]
// STATUS: %[[OTHER_STATUS:.*]] = runtime.status.from_bits %arg1
// STATUS-NEXT: %[[OTHER_OK:.*]] = runtime.status.is %[[OTHER_STATUS]], <ok>
// STATUS-NEXT: cf.cond_br %[[OTHER_OK]], ^{{bb[0-9]+}}, ^[[OTHER_FAILED:bb[0-9]+]]
// STATUS: ^[[PUSH_FAILED]]:
// STATUS-NEXT: %[[PUSH_BITS:.*]] = runtime.status.to_bits %[[PUSH_STATUS]]
// STATUS-NEXT: simulation.return %[[PUSH_BITS]] : i32
// STATUS-NEXT: ^[[OTHER_FAILED]]:
// STATUS-NEXT: %[[OTHER_BITS:.*]] = runtime.status.to_bits %[[OTHER_STATUS]]
// STATUS-NEXT: schedule.gc.root_range.pop %[[RECORD]] : !llvm.ptr
// STATUS-NEXT: simulation.return %[[OTHER_BITS]] : i32

// NATIVE-LABEL: llvm.func @plain(
// NATIVE: %[[PUSHED:.*]] = llvm.call @talos_rt_v1_gc_managed_root_range_push(
// NATIVE: llvm.cond_br %{{.*}}, ^{{bb[0-9]+}}, ^[[PUSH_FAILED:bb[0-9]+]]
// NATIVE: llvm.cond_br %{{.*}}, ^{{bb[0-9]+}}, ^[[OTHER_FAILED:bb[0-9]+]]
// NATIVE: ^[[PUSH_FAILED]]:
// NATIVE-NEXT: llvm.return %[[PUSHED]] : i32
// NATIVE-NEXT: ^[[OTHER_FAILED]]:
// NATIVE: llvm.call @talos_rt_v1_gc_managed_root_range_pop(

// NATIVE-LABEL: llvm.func @suspending.__talos_coro_ramp(
// NATIVE: %[[PUSHED:.*]] = llvm.call @talos_rt_v1_gc_managed_root_range_push(
// NATIVE: llvm.cond_br %{{.*}}, ^{{bb[0-9]+}}, ^[[PUSH_FAILED:bb[0-9]+]]
// NATIVE: llvm.cond_br %{{.*}}, ^{{bb[0-9]+}}, ^[[OTHER_FAILED:bb[0-9]+]]
// NATIVE: ^[[PUSH_FAILED]]:
// NATIVE-NEXT: %[[STATUS_FIELD:.*]] = llvm.getelementptr
// NATIVE-NEXT: llvm.store %[[PUSHED]], %[[STATUS_FIELD]]
// NATIVE-NEXT: llvm.br
// NATIVE-NEXT: ^[[OTHER_FAILED]]:
// NATIVE: llvm.call @talos_rt_v1_gc_managed_root_range_pop(

module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @roots {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "roots.fn"
    simulation.code_unit.decl 2 in 0 initial hierarchy "roots.plain"
    simulation.code_unit.decl 3 in 0 initial hierarchy "roots.suspending"
    simulation.func private @fn(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %bits: i32 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 8 : i32} {
      %one = llvm.mlir.constant(1 : i64) : i64
      %record = llvm.alloca %one x !llvm.struct<(ptr, i64, ptr, i64)> : (i64) -> !llvm.ptr
      %slots = llvm.alloca %one x !llvm.ptr : (i64) -> !llvm.ptr
      %pushed = schedule.gc.root_range.push %record slots %slots count %one : !llvm.ptr, !llvm.ptr
      %push_status = runtime.status.from_bits %pushed
      simulation.status.check %push_status root_range_push
      %status = runtime.status.from_bits %bits
      simulation.status.check %status
      schedule.gc.root_range.pop %record : !llvm.ptr
      simulation.return
    }
    simulation.func @plain(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %bits: i32 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 1 : i32} {
      %one = llvm.mlir.constant(1 : i64) : i64
      %record = llvm.alloca %one x !llvm.struct<(ptr, i64, ptr, i64)> : (i64) -> !llvm.ptr
      %slots = llvm.alloca %one x !llvm.ptr : (i64) -> !llvm.ptr
      %pushed = schedule.gc.root_range.push %record slots %slots count %one : !llvm.ptr, !llvm.ptr
      %push_status = runtime.status.from_bits %pushed
      simulation.status.check %push_status root_range_push
      %status = runtime.status.from_bits %bits
      simulation.status.check %status
      schedule.gc.root_range.pop %record : !llvm.ptr
      simulation.return
    }
    simulation.func @suspending(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %bits: i32 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 1 : i32} {
      %one = llvm.mlir.constant(1 : i64) : i64
      %record = llvm.alloca %one x !llvm.struct<(ptr, i64, ptr, i64)> : (i64) -> !llvm.ptr
      %slots = llvm.alloca %one x !llvm.ptr : (i64) -> !llvm.ptr
      %pushed = schedule.gc.root_range.push %record slots %slots count %one : !llvm.ptr, !llvm.ptr
      %push_status = runtime.status.from_bits %pushed
      simulation.status.check %push_status root_range_push
      %status = runtime.status.from_bits %bits
      simulation.status.check %status
      schedule.gc.root_range.pop %record : !llvm.ptr
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^done
    ^done:
      simulation.return
    }
  }
}
