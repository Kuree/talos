// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval sim-opt-level=3 closed-executable=true' | FileCheck %s --implicit-check-not='llvm.call @talos_rt_v1_scheduler_nba('

// IEEE 1800-2023 4.9.4, 13.3.2, 13.5: a static output formal persists
// between calls. The first return copies its initial X; the NBA updates the
// formal later, so the second return copies 8'h11. The implicit copy-out
// read makes the formal's NBA live even with no hierarchical reader.
// CHECK-LABEL: llvm.func @unit_1(
// CHECK-SAME: %[[VALUE:arg2]]: i8, %[[UNKNOWN:arg3]]: i8) -> i32
// CHECK-DAG: %[[ACC:.*]] = llvm.mlir.addressof @__talos_aot_nba_accumulator_0
// CHECK-DAG: %[[DIRTY:.*]] = llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// CHECK-DAG: %[[MASK:.*]] = llvm.mlir.constant(255 : i64)
// CHECK-DAG: %[[BIT:.*]] = llvm.mlir.constant(1 : i64)
// CHECK: %[[STAGED_UNKNOWN:.*]] = llvm.zext %[[UNKNOWN]] : i8 to i64
// CHECK-NEXT: %[[STAGED_VALUE:.*]] = llvm.zext %[[VALUE]] : i8 to i64
// CHECK-NEXT: %[[FORMAL:.*]] = llvm.getelementptr %{{.*}}[1]
// CHECK: %[[VALUE_BITS:.*]] = llvm.and %[[STAGED_VALUE]], %[[MASK]] : i64
// CHECK: %[[MERGED_VALUE:.*]] = llvm.or %{{.*}}, %[[VALUE_BITS]] : i64
// CHECK-NEXT: llvm.store %[[MERGED_VALUE]], %[[ACC]]
// CHECK-NEXT: %[[UNKNOWN_BITS:.*]] = llvm.and %[[STAGED_UNKNOWN]], %[[MASK]] : i64
// CHECK-NEXT: %[[UNKNOWN_ADDR:.*]] = llvm.getelementptr %[[ACC]][32]
// CHECK: %[[MERGED_UNKNOWN:.*]] = llvm.or %{{.*}}, %[[UNKNOWN_BITS]] : i64
// CHECK-NEXT: llvm.store %[[MERGED_UNKNOWN]], %[[UNKNOWN_ADDR]]
// CHECK: %[[OLD_DIRTY:.*]] = llvm.load %[[DIRTY]]
// CHECK-NEXT: %[[NEW_DIRTY:.*]] = llvm.or %[[OLD_DIRTY]], %[[BIT]] : i64
// CHECK-NEXT: llvm.store %[[NEW_DIRTY]], %[[DIRTY]]
// CHECK: llvm.load %[[FORMAL]]

`timescale 1ns/1ps
module top;
  logic [7:0] q=0;
  task static put(output logic [7:0] out, input logic [7:0] value);
    out<=value;
  endtask
  initial begin
    put(q,8'h11);
    #1; $display("%b",q);
    put(q,8'h22);
    #1; $display("%b",q);
    $finish;
  end
endmodule
