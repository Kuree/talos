// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=auto sim-opt-level=3' -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=__talos_eval_kernel_retry_4294967295_v1 < %t.mlir

// IEEE 1800-2023 6.3.1: both bodies of a kernel are correct on known state, so
// which one runs is only a choice of code to keep hot. An X/Z that keeps toggling
// must not keep the whole-body copy hot as well: after a failed certificate the
// kernel stays on its four-state source for 63 activations before it asks again.
// A proof recovered in the meantime clears the pending bit, which skips this
// query. A runtime-owned actor's analysis-only node has no owner, and no retry.
// CHECK: llvm.mlir.global internal @__talos_eval_kernel_retry_[[OWNER:[0-9]+]]_v1(0 : i8)
// CHECK-LABEL: llvm.func internal @__talos_eval_clocked_kernel_ready_v1(%arg0: i64, %arg1: !llvm.ptr) -> i1
// CHECK-DAG: %[[TRUE:.*]] = llvm.mlir.constant(true)
// CHECK-DAG: %[[FALSE:.*]] = llvm.mlir.constant(false)
// CHECK-DAG: %[[INTERVAL:.*]] = llvm.mlir.constant(63 : i8)
// CHECK-DAG: %[[ONE:.*]] = llvm.mlir.constant(1 : i8)
// CHECK: %[[LEFT:.*]] = llvm.load %arg1
// CHECK: llvm.cond_br %{{.*}}, ^[[WAIT:bb[0-9]+]], ^[[PROBE:bb[0-9]+]]
// CHECK: ^[[WAIT]]:
// CHECK-NEXT: %[[NEXT:.*]] = llvm.sub %[[LEFT]], %[[ONE]]
// CHECK-NEXT: llvm.store %[[NEXT]], %arg1
// CHECK-NEXT: llvm.return %[[FALSE]]
// CHECK: ^[[PROBE]]:
// CHECK-NEXT: %[[KNOWN:.*]] = llvm.call @__talos_eval_kernel_promotion_ready_v1(%arg0)
// CHECK-NEXT: llvm.cond_br %[[KNOWN]], ^[[READY:bb[0-9]+]], ^[[FAILED:bb[0-9]+]]
// CHECK: ^[[FAILED]]:
// CHECK-NEXT: llvm.store %[[INTERVAL]], %arg1
// CHECK-NEXT: llvm.return %[[FALSE]]
// CHECK: ^[[READY]]:
// CHECK-NEXT: llvm.return %[[TRUE]]

// The kernel's dispatch entry and its direct run share that one retry state.
// CHECK-LABEL: llvm.func @__talos_aot_schedule_run_v1(
// CHECK: llvm.call @__talos_eval_clocked_kernel_ready_v1(
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CHECK: llvm.call @__talos_eval_clocked_kernel_ready_v1(

module clocked_kernel_retry;
  logic clk = 0;
  logic [7:0] seed = 8'h35, a = 0, b = 0, c = 0, unknown;
  always #5 clk = ~clk;
  always_ff @(posedge clk) a <= a + seed;
  always_ff @(posedge clk) b <= b ^ a;
  always_ff @(posedge clk) c <= c + (unknown & b);
  initial begin
    #1000 unknown = 8'h0f;
    #1000 unknown = 8'hxx;
    #1000 $finish;
  end
endmodule
