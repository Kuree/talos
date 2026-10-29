// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(talos-native-share-scoped-temporaries))' -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos-opt %t.mlir --pass-pipeline='builtin.module(llvm.func(talos-native-share-scoped-temporaries))' | diff %t.mlir -
// RUN: talos-opt %s --mlir-disable-threading --pass-pipeline='builtin.module(llvm.func(talos-native-share-scoped-temporaries))' | diff %t.mlir -
// RUN: talos-translate --mlir-to-llvmir %t.mlir | %llvm_dist/bin/opt -passes=verify -disable-output

// Direct output consumes borrowed ABI storage synchronously. Payload pointers
// embedded in an argument array must stay live through its last display.
// SV variables and deferred output keep their own lifetimes (LRM 21.2.1/21.2.2).
!item = !llvm.struct<(i32, i32, i64, ptr, ptr)>
!environment = !llvm.struct<(ptr, i64, ptr, i64, i32, i32, ptr, i64, i64)>
module {
  llvm.func @talos_rt_v1_eval_display(!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
  llvm.func @unknown(!llvm.ptr)

  // CHECK-LABEL: llvm.func @nested_payloads
  // CHECK-COUNT-4: llvm.intr.lifetime.start
  // CHECK: llvm.call @talos_rt_v1_eval_display
  // CHECK-NOT: llvm.intr.lifetime.end
  // CHECK: llvm.call @talos_rt_v1_eval_display
  // CHECK-COUNT-4: llvm.intr.lifetime.end
  // CHECK-NEXT: llvm.return
  llvm.func @nested_payloads(%ctx: !llvm.ptr, %value: i64, %unknown: i64) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %two = llvm.mlir.constant(2 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %radix = llvm.mlir.constant(16 : i32) : i32
    %value_slot = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    %unknown_slot = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    %items = llvm.alloca %two x !item : (i64) -> !llvm.ptr
    %env = llvm.alloca %one x !environment : (i64) -> !llvm.ptr
    llvm.store %value, %value_slot : i64, !llvm.ptr
    llvm.store %unknown, %unknown_slot : i64, !llvm.ptr
    %empty = llvm.mlir.zero : !item
    %arg0 = llvm.insertvalue %value_slot, %empty[3] : !item
    %arg1 = llvm.insertvalue %unknown_slot, %arg0[4] : !item
    %first = llvm.getelementptr %items[0] : (!llvm.ptr) -> !llvm.ptr, !item
    %second = llvm.getelementptr %items[%out] : (!llvm.ptr, i32) -> !llvm.ptr, !item
    llvm.store %arg1, %first : !item, !llvm.ptr
    llvm.store %empty, %second : !item, !llvm.ptr
    %format = llvm.mlir.zero : !environment
    llvm.store %format, %env : !environment, !llvm.ptr
    %status0 = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %radix, %items, %two, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.store %unknown, %value_slot : i64, !llvm.ptr
    %status1 = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %radix, %items, %two, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.return
  }

  // A start cannot discard contents carried from a preceding loop iteration.
  // One initialized element of a two-element object is insufficient proof.
  // CHECK-LABEL: llvm.func @partial_loop
  // CHECK-NOT: lifetime
  // CHECK: llvm.return
  llvm.func @partial_loop(%ctx: !llvm.ptr, %env: !llvm.ptr, %again: i1) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %two = llvm.mlir.constant(2 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %items = llvm.alloca %two x !item : (i64) -> !llvm.ptr
    llvm.br ^loop
  ^loop:
    %empty = llvm.mlir.zero : !item
    llvm.store %empty, %items : !item, !llvm.ptr
    %status = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.cond_br %again, ^loop, ^done
  ^done:
    llvm.return
  }

  // Complete initialization can open a fresh scope on every loop iteration.
  // CHECK-LABEL: llvm.func @initialized_loop
  // CHECK: ^bb1:
  // CHECK: llvm.intr.lifetime.start
  // CHECK: llvm.store
  // CHECK: llvm.call @talos_rt_v1_eval_display
  // CHECK-NEXT: llvm.intr.lifetime.end
  // CHECK-NEXT: llvm.cond_br
  llvm.func @initialized_loop(%ctx: !llvm.ptr, %env: !llvm.ptr, %again: i1) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %items = llvm.alloca %one x !item : (i64) -> !llvm.ptr
    llvm.br ^loop
  ^loop:
    %empty = llvm.mlir.zero : !item
    llvm.store %empty, %items : !item, !llvm.ptr
    %status = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.cond_br %again, ^loop, ^done
  ^done:
    llvm.return
  }

  // The argument array's later escape also keeps its nested payload alive.
  // CHECK-LABEL: llvm.func @parent_escape
  // CHECK-NOT: lifetime
  // CHECK: llvm.call @unknown
  // CHECK-NOT: lifetime
  // CHECK: llvm.return
  llvm.func @parent_escape(%ctx: !llvm.ptr, %env: !llvm.ptr, %value: i64) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %payload = llvm.alloca %one x i64 : (i64) -> !llvm.ptr
    %items = llvm.alloca %one x !item : (i64) -> !llvm.ptr
    llvm.store %value, %payload : i64, !llvm.ptr
    %empty = llvm.mlir.zero : !item
    %arg = llvm.insertvalue %payload, %empty[3] : !item
    llvm.store %arg, %items : !item, !llvm.ptr
    %status = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.call @unknown(%items) : (!llvm.ptr) -> ()
    llvm.return
  }

  // An unproved dynamic index cannot establish complete initialization.
  // CHECK-LABEL: llvm.func @dynamic_index
  // CHECK-NOT: lifetime
  // CHECK: llvm.return
  llvm.func @dynamic_index(%ctx: !llvm.ptr, %env: !llvm.ptr, %index: i64) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %two = llvm.mlir.constant(2 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %items = llvm.alloca %two x !item : (i64) -> !llvm.ptr
    %empty = llvm.mlir.zero : !item
    llvm.store %empty, %items : !item, !llvm.ptr
    %next = llvm.getelementptr %items[%index] : (!llvm.ptr, i64) -> !llvm.ptr, !item
    llvm.store %empty, %next : !item, !llvm.ptr
    %status = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.return
  }

  // CHECK-LABEL: llvm.func @cross_block
  // CHECK-NOT: lifetime
  // CHECK: llvm.return
  llvm.func @cross_block(%ctx: !llvm.ptr, %env: !llvm.ptr) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %items = llvm.alloca %one x !item : (i64) -> !llvm.ptr
    %empty = llvm.mlir.zero : !item
    llvm.store %empty, %items : !item, !llvm.ptr
    llvm.br ^output
  ^output:
    %status = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.return
  }

  // Context arguments have no borrowing contract, even on the same call.
  // CHECK-LABEL: llvm.func @context_escape
  // CHECK-NOT: lifetime
  // CHECK: llvm.return
  llvm.func @context_escape(%env: !llvm.ptr) {
    %one = llvm.mlir.constant(1 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %items = llvm.alloca %one x !item : (i64) -> !llvm.ptr
    %empty = llvm.mlir.zero : !item
    llvm.store %empty, %items : !item, !llvm.ptr
    %status = llvm.call @talos_rt_v1_eval_display(%items, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.return
  }

  // CHECK-LABEL: llvm.func @coroutine
  // CHECK-NOT: lifetime
  // CHECK: llvm.return
  llvm.func @coroutine(%ctx: !llvm.ptr, %env: !llvm.ptr) attributes {passthrough = ["presplitcoroutine"]} {
    %one = llvm.mlir.constant(1 : i64) : i64
    %out = llvm.mlir.constant(1 : i32) : i32
    %items = llvm.alloca %one x !item : (i64) -> !llvm.ptr
    %empty = llvm.mlir.zero : !item
    llvm.store %empty, %items : !item, !llvm.ptr
    %status = llvm.call @talos_rt_v1_eval_display(%ctx, %out, %out, %out, %items, %one, %env) : (!llvm.ptr, i32, i32, i32, !llvm.ptr, i64, !llvm.ptr) -> i32
    llvm.return
  }
}
