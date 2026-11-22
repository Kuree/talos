// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval sim-opt-level=3 stop-after=materialize' | FileCheck %s

// The port's 130-bit always_comb output is copied to `bus` through byte
// snapshots: a handle-addressed transition of the `_bytes` form. The
// assertion's disable condition reads bits of `bus` and must see each
// assignment to it whole (IEEE 1800-2023 9.4.2, 16.12), so AOT planning
// keeps it one runtime publication from the executing actor. The generated body itself wakes the direct observers
// slice by slice, so the runtime call is the projected publication. Each
// 64-bit slice loads from the snapshots at its byte offset; the last, bits
// 128-129, loads its byte and truncates it, since a load of an integer that
// is not a whole number of bytes from memory that no store of that type
// wrote is undefined (LLVM LangRef, load), and the snapshots are copies of
// state bytes. The two-state variant runs while no unknown bit is set: it
// passes no unknown snapshots, the null pointer, and its slices' unknown
// words are 0.
// The input is SystemVerilog because the whole publication depends on the
// native fanout plan of a computed event expression.
module wide_port(input logic [129:0] left, right, output logic [129:0] bus);
  always_comb bus = left ^ right;
endmodule
module top;
  bit clk;
  logic [129:0] left = '0, right = '0, bus;
  int changes;
  wide_port port(left, right, bus);
  always #5 clk = !clk;
  always @(bus) changes++;
  assert property (@(posedge clk) disable iff (bus[129] != bus[0]) 1);
  initial #6 left = {1'b1, 128'b0, 1'b1};
endmodule

// CHECK-LABEL: func.func private @unit_9.__talos_eval_body_0(
// CHECK: "llvm.intr.memcpy"(%[[NEW:[0-9]+]], %{{[0-9]+}}, %{{[0-9]+}})
// CHECK: "llvm.intr.memcpy"(%[[NEW_UNKNOWN:[0-9]+]], %{{[0-9]+}}, %{{[0-9]+}})
// CHECK: "llvm.intr.memcpy"(%[[OLD:[0-9]+]], %{{[0-9]+}}, %{{[0-9]+}})
// CHECK: "llvm.intr.memcpy"(%[[OLD_UNKNOWN:[0-9]+]], %{{[0-9]+}}, %{{[0-9]+}})
// CHECK: %[[CONTEXT:[0-9]+]] = llvm.load %{{[0-9]+}} {alignment = 8 : i64} : !llvm.ptr -> !llvm.ptr
// CHECK-NEXT: llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: llvm.getelementptr %[[OLD]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_UNKNOWN]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: llvm.getelementptr %[[NEW]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: llvm.getelementptr %[[NEW_UNKNOWN]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK: schedule.ready.update @__talos_aot_model_ingress_v1
// CHECK: llvm.mlir.constant(64 : i64) : i64
// CHECK-NEXT: llvm.getelementptr %[[OLD]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK: schedule.ready.update @__talos_aot_model_ingress_v1
// CHECK: llvm.mlir.constant(128 : i64) : i64
// CHECK-NEXT: %[[OLD_TOP:[0-9]+]] = llvm.getelementptr %[[OLD]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: %[[OLD_BITS_BYTE:[0-9]+]] = llvm.load %[[OLD_TOP]] {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: %[[OLD_BITS:[0-9]+]] = llvm.trunc %[[OLD_BITS_BYTE]] : i8 to i2
// CHECK-NEXT: %[[OLD_WORD:[0-9]+]] = llvm.zext %[[OLD_BITS]] : i2 to i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_UNKNOWN]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i2
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i2 to i64
// CHECK-NEXT: llvm.getelementptr %[[NEW]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i2
// CHECK-NEXT: %[[NEW_WORD:[0-9]+]] = llvm.zext %{{[0-9]+}} : i2 to i64
// CHECK-NEXT: llvm.getelementptr %[[NEW_UNKNOWN]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i2
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i2 to i64
// CHECK-NEXT: arith.xori %[[OLD_WORD]], %[[NEW_WORD]] : i64
// CHECK-NEXT: arith.xori %{{[0-9]+}}, %{{[0-9]+}} : i64
// CHECK-NEXT: %[[TOP_CHANGES:[0-9]+]] = arith.ori %{{[0-9]+}}, %{{[0-9]+}} : i64
// CHECK-NEXT: llvm.mlir.constant(3 : i64) : i64
// CHECK-NEXT: llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[TOP_MASK:[0-9]+]] = llvm.mlir.constant(3 : i64) : i64
// CHECK-NEXT: arith.andi %[[TOP_CHANGES]], %[[TOP_MASK]] : i64
// CHECK: schedule.ready.update @__talos_aot_model_ingress_v1
// CHECK: %[[ACTOR:[0-9]+]] = llvm.mlir.constant({{[0-9]+}} : i32) : i32
// CHECK-NEXT: %[[WIDTH:[0-9]+]] = llvm.mlir.constant(130 : i64) : i64
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_projected(%[[CONTEXT]], %[[ACTOR]], %{{[^,]+}}, %[[WIDTH]], %[[OLD]], %[[OLD_UNKNOWN]], %[[NEW]], %[[NEW_UNKNOWN]]) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> ()
// CHECK-NOT: transition
// CHECK-NOT: !llvm.ptr -> i2{{$}}
// CHECK: return

// CHECK-LABEL: func.func private @unit_9.__talos_eval_body_0.__talos_two_state_0(
// CHECK: "llvm.intr.memcpy"(%[[TWO_STATE_NEW:[0-9]+]], %{{[0-9]+}}, %{{[0-9]+}})
// CHECK: "llvm.intr.memcpy"(%[[TWO_STATE_OLD:[0-9]+]], %{{[0-9]+}}, %{{[0-9]+}})
// CHECK: llvm.mlir.constant(128 : i64) : i64
// CHECK-NEXT: llvm.getelementptr %[[TWO_STATE_OLD]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i2
// CHECK-NEXT: %[[TWO_STATE_OLD_WORD:[0-9]+]] = llvm.zext %{{[0-9]+}} : i2 to i64
// CHECK-NEXT: %[[NO_OLD_UNKNOWN:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: llvm.getelementptr %[[TWO_STATE_NEW]][16] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i8
// CHECK-NEXT: llvm.trunc %{{[0-9]+}} : i8 to i2
// CHECK-NEXT: %[[TWO_STATE_NEW_WORD:[0-9]+]] = llvm.zext %{{[0-9]+}} : i2 to i64
// CHECK-NEXT: %[[NO_NEW_UNKNOWN:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: arith.xori %[[TWO_STATE_OLD_WORD]], %[[TWO_STATE_NEW_WORD]] : i64
// CHECK-NEXT: arith.xori %[[NO_OLD_UNKNOWN]], %[[NO_NEW_UNKNOWN]] : i64
// CHECK: %[[NO_OLD_UNKNOWN_SNAPSHOT:[0-9]+]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NEXT: %[[NO_NEW_UNKNOWN_SNAPSHOT:[0-9]+]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_projected(%{{[0-9]+}}, %{{[0-9]+}}, %{{[^,]+}}, %{{[0-9]+}}, %[[TWO_STATE_OLD]], %[[NO_OLD_UNKNOWN_SNAPSHOT]], %[[TWO_STATE_NEW]], %[[NO_NEW_UNKNOWN_SNAPSHOT]])
