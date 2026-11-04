// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval' -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos %s -o %t.exe
// RUN: env TALOS_RT_VERIFY_PROMOTION_SLICES=1 %t.exe | FileCheck %s --check-prefix=OUT

// IEEE 1800-2023 6.3.1: the dynamic-index read of `mem` depends on the whole
// 8192-bit memory. That wide proof dependency becomes a promotion slice: the
// runtime counts the memory's X/Z bits, X/Z reports invalidate its dependent
// proof, and only a count reaching zero rechecks it. The memory leaves the
// range index; the global invalidator recounts the slice from the plane.
// CHECK-DAG: llvm.mlir.global internal constant @__talos_eval_promotion_slice_ranges_v1(dense<[8, 8200]>
// CHECK-DAG: llvm.mlir.global internal constant @__talos_eval_promotion_slice_starts_v1(dense<[0, 1]>
// CHECK-DAG: llvm.mlir.global internal constant @__talos_eval_promotion_slice_dependents_v1(dense<5>
// CHECK-DAG: llvm.mlir.global internal @__talos_eval_promotion_slice_counts_v1(dense<0>
// CHECK-NOT: schedule.eval.proof_slices
// CHECK-NOT: @__talos_eval_proof_dependencies_v1(dense<{{\[\[}}8, 8200,
// CHECK-LABEL: llvm.func @__talos_eval_promotion_recheck_range_v1(
// CHECK: %[[KNOWN:.*]] = llvm.mlir.constant(0 : i32)
// CHECK: llvm.call @talos_rt_v1_native_promotion_slices_adjust({{.*}}, %arg0, %arg1, %[[KNOWN]])
// CHECK-LABEL: llvm.func @__talos_eval_promotion_invalidate_range_v1(
// CHECK: %[[UNKNOWN:.*]] = llvm.mlir.constant(1 : i32)
// CHECK: llvm.call @talos_rt_v1_native_promotion_slices_adjust({{.*}}, %arg0, %arg1, %[[UNKNOWN]])
// CHECK-LABEL: llvm.func @__talos_eval_promotion_invalidate_v1(
// CHECK: llvm.call @talos_rt_v1_native_promotion_slices_recount(

// The memory fills with known values while being read; the counts stay exact,
// which the verifier checks at exit.
// OUT: 3 q=03
// OUT-NEXT: 4 q=06
// OUT-NEXT: 5 q=09
// OUT-NEXT: 6 q=0c
// OUT-NEXT: 7 q=0f
// OUT-NOT: promotion slice

module top;
  logic clk = 0;
  logic [7:0] mem [0:1023];
  logic [9:0] waddr = 0, raddr = 0;
  logic [7:0] q, wdata = 0;
  int cycle = 0;
  always #5 clk = ~clk;
  always_ff @(posedge clk) q <= mem[raddr];
  always_ff @(posedge clk) begin
    mem[waddr] <= wdata;
    waddr <= waddr + 1;
    wdata <= wdata + 3;
    raddr <= waddr;
  end
  always @(posedge clk) begin
    cycle <= cycle + 1;
    if (cycle > 2 && cycle < 8) $display("%0d q=%h", cycle, q);
    if (cycle == 8) $finish;
  end
endmodule
