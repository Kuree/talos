// RUN: talos-opt %s --inline | FileCheck %s

// Typed state accesses are plain memory accesses: a body holding them
// inlines like one holding LLVM loads and stores. Handle-addressed accesses
// and transitions inline like the runtime calls they stand for.
module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.func @use(!llvm.ptr)
  llvm.func @member(%v: i8) -> i8 {
    %a = schedule.state.address @__talos_state_value : !llvm.ptr
    llvm.call @use(%a) : (!llvm.ptr) -> ()
    schedule.state.store %v, @__talos_state_value[2] {alignment = 1 : i64} : i8
    %x = schedule.state.load @__talos_state_value[3] {alignment = 1 : i64} : i8
    llvm.return %x : i8
  }
  // CHECK-LABEL: llvm.func @group(
  // CHECK-NOT: llvm.call @member
  // CHECK: schedule.state.address @__talos_state_value
  // CHECK: schedule.state.store %{{.*}}, @__talos_state_value[2]
  // CHECK: schedule.state.load @__talos_state_value[3]
  llvm.func @group(%v: i8) -> i8 {
    %x = llvm.call @member(%v) : (i8) -> i8
    llvm.return %x : i8
  }

  llvm.func @handle_member(%context: !llvm.ptr, %handle: i64, %v: i8, %buffer: !llvm.ptr) -> i8 {
    %x = schedule.state.load_handle @__talos_state_value[%handle] {state_bits = 128 : i64} : i8
    %changed = schedule.state.store_handle %v, @__talos_state_value[%handle] {state_bits = 128 : i64} : i8
    schedule.state.load_handle_bytes @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 65 : i64}
    schedule.state.store_handle_bytes %buffer, @__talos_state_value[%handle] changed %buffer {state_bits = 128 : i64, width = 65 : i64}
    schedule.state.frame_store %v to %handle {state_bits = 128 : i64} : i8
    %status = schedule.state.load_automatic %context, %handle into %buffer {width = 65 : i64}
    schedule.transition.handle %context, %handle from %x to %v : i8
    schedule.transition.handle_bytes %context, %handle from %buffer to %buffer {width = 65 : i64}
    llvm.return %x : i8
  }
  // CHECK-LABEL: llvm.func @handle_group(
  // CHECK-NOT: llvm.call @handle_member
  // CHECK: schedule.state.load_handle @__talos_state_value
  // CHECK-NEXT: schedule.state.store_handle %{{.*}}, @__talos_state_value
  // CHECK-NEXT: schedule.state.load_handle_bytes @__talos_state_value
  // CHECK-NEXT: schedule.state.store_handle_bytes %{{.*}}, @__talos_state_value
  // CHECK-NEXT: schedule.state.frame_store
  // CHECK-NEXT: schedule.state.load_automatic
  // CHECK-NEXT: schedule.transition.handle %
  // CHECK-NEXT: schedule.transition.handle_bytes %
  // CHECK-NOT: llvm.call @handle_member
  // CHECK: llvm.return
  llvm.func @handle_group(%context: !llvm.ptr, %handle: i64, %v: i8, %buffer: !llvm.ptr) -> i8 {
    %x = llvm.call @handle_member(%context, %handle, %v, %buffer) : (!llvm.ptr, i64, i8, !llvm.ptr) -> i8
    llvm.return %x : i8
  }
}
