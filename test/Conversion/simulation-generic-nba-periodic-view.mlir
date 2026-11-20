// RUN: talos-opt %s --materialize-native-eval-transactions -o %t.mlir
// RUN: FileCheck %s < %t.mlir

// The two register bodies read the same queue index. The first capture adds
// a pending update. An intervening external handoff changes the binding for
// the next capture. Both ordinary entry points retain their original ABI.
// CHECK-LABEL: llvm.func internal @first.__talos_queue_view(
// CHECK: llvm.load
// CHECK-NOT: llvm.call @talos_rt_v1_scheduler_generic_nba_words
// CHECK: llvm.return
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK: llvm.call @owner_a.__talos_queue_view(
// CHECK: llvm.call @owner_b.__talos_queue_view(
// CHECK: llvm.store %{{.*}}, %[[SLOT:.*]] {{.*}}: !llvm.ptr, !llvm.ptr
// CHECK-NEXT: llvm.call @rebind(
// CHECK: llvm.load %[[SLOT]]
// CHECK: llvm.call @talos_rt_v1_scheduler_generic_nba_words(
// CHECK: llvm.call @owner_b.__talos_queue_view(

module attributes {schedule.force_generic_nba, schedule.eval.runtime_calendar, native.closed_executable} {
  llvm.mlir.global internal @__talos_current_context() : !llvm.ptr {
    %null = llvm.mlir.zero : !llvm.ptr
    llvm.return %null : !llvm.ptr
  }
  llvm.mlir.global internal @first_word(10 : i64) : i64
  llvm.mlir.global internal @sum(0 : i64) : i64
  llvm.func @talos_rt_v1_scheduler_generic_nba_words(!llvm.ptr, i32) -> !llvm.ptr
  llvm.func @rebind()
  llvm.func @first(%arg: !llvm.ptr) attributes {schedule.eval.raw_captures} {
    %p = llvm.mlir.addressof @__talos_current_context : !llvm.ptr
    %ctx = llvm.load %p : !llvm.ptr -> !llvm.ptr
    %id = llvm.mlir.constant(2 : i32) : i32
    %view = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%ctx, %id) : (!llvm.ptr, i32) -> !llvm.ptr
    %value = llvm.load %view : !llvm.ptr -> i64
    %out = llvm.mlir.addressof @sum : !llvm.ptr
    llvm.store %value, %out : i64, !llvm.ptr
    %bit = llvm.mlir.constant(1 : i64) : i64
    %pending = llvm.or %value, %bit : i64
    %word = llvm.mlir.addressof @first_word : !llvm.ptr
    llvm.store %pending, %word : i64, !llvm.ptr
    llvm.return
  }
  llvm.func @second(%arg: !llvm.ptr) attributes {schedule.eval.raw_captures} {
    %p = llvm.mlir.addressof @__talos_current_context : !llvm.ptr
    %ctx = llvm.load %p : !llvm.ptr -> !llvm.ptr
    %id = llvm.mlir.constant(9 : i32) : i32
    %view = llvm.call @talos_rt_v1_scheduler_generic_nba_words(%ctx, %id) : (!llvm.ptr, i32) -> !llvm.ptr
    %value = llvm.load %view : !llvm.ptr -> i64
    %out = llvm.mlir.addressof @sum : !llvm.ptr
    %prior = llvm.load %out : !llvm.ptr -> i64
    %next = llvm.add %prior, %value : i64
    llvm.store %next, %out : i64, !llvm.ptr
    llvm.return
  }
  llvm.func @owner_a(%ctx: !llvm.ptr) -> i32 attributes {schedule.eval.infallible} {
    llvm.call @first(%ctx) : (!llvm.ptr) -> ()
    %ok = llvm.mlir.constant(0 : i32) : i32
    llvm.return %ok : i32
  }
  llvm.func @owner_b(%ctx: !llvm.ptr) -> i32 attributes {passthrough = ["alwaysinline"]} {
    llvm.call @second(%ctx) : (!llvm.ptr) -> ()
    %ok = llvm.mlir.constant(0 : i32) : i32
    llvm.return %ok : i32
  }
  llvm.func @__talos_aot_schedule_run_v1(%ctx: !llvm.ptr) {
    %first = llvm.call @owner_a(%ctx) : (!llvm.ptr) -> i32
    %second = llvm.call @owner_b(%ctx) : (!llvm.ptr) -> i32
    llvm.call @rebind() : () -> ()
    %third = llvm.call @owner_b(%ctx) : (!llvm.ptr) -> i32
    llvm.return
  }
}
