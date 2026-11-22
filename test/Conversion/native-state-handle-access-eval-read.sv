// RUN: talos -emit-slang %s -o %t.slang.mlir
// RUN: talos-opt %t.slang.mlir --test-talos-native-backend='scheduler=eval stop-after=materialize' --mlir-print-ir-after=prepare-native-fragments -o %t.mlir 2> %t.typed.mlir
// RUN: FileCheck %s --check-prefix=TYPED < %t.typed.mlir
// RUN: FileCheck %s --implicit-check-not=schedule.state.load_handle --implicit-check-not=schedule.state.store_handle < %t.mlir

// The leaf's register reads an input port bound to an array element that the
// initial block forces, so its generated eval body reads the port behind the
// static specialization guard through the port's stable handle: native
// lowering reads each plane as a scalar value. The port's continuous
// assignment copies the element through byte buffers, the `_bytes` form. The
// port is wider than a machine word; the read is integer arithmetic of its
// width. AOT planning reads each access by its plane, width and handle and
// replaces it with a clamped read of the canonical plane: the bits inside the
// root keep their value, and the others take the value of an invalid index,
// 0 in the value plane and 1 in the unknown plane (IEEE 1800-2023 7.4.5,
// 11.5.1). A scalar read becomes that value; a `_bytes` read stores it to its
// buffer. No typed access is left. The copy's transition then publishes the
// buffers word by word (9.4.2), loading each slice at its byte offset.
// The pipeline stops after materialize-native-processes: the guard is a
// runtime call that the eval call closure check rejects later, so the driver
// compiles this design again with the generic scheduler
// (Driver/generic-scheduler-fallback.sv).
module leaf(input var logic clk, input var logic [64:0] d,
            output var logic [64:0] q);
  always_ff @(posedge clk) q <= d;
endmodule

module top;
  logic clk = 0;
  logic [64:0] data[2] = '{1, 5};
  logic [64:0] result[2];
  leaf u(clk, data[1], result[0]);
  always #5 clk = ~clk;
  initial begin
    #6 force u.d = 65'h1_0000_0000_0000_000a;
    #10 release u.d;
  end
endmodule

// TYPED-LABEL: IR Dump After PrepareNativeFragmentsPass
// TYPED-LABEL: simulation.func private @unit_2.__talos_eval_body_0(
// TYPED: %[[VALUE:[0-9]+]] = schedule.state.load_handle @__talos_state_value[%[[PORT:c[0-9]+_i64]]] {state_bits = [[STATE_BITS:[0-9]+]] : i64} : i65
// TYPED-NEXT: cf.br ^{{bb[0-9]+}}(%[[VALUE]] : i65)
// TYPED: %[[UNKNOWN:[0-9]+]] = schedule.state.load_handle @__talos_state_unknown[%[[PORT]]] {state_bits = [[STATE_BITS]] : i64} : i65
// TYPED-NEXT: cf.br ^{{bb[0-9]+}}(%[[UNKNOWN]] : i65)
// TYPED-LABEL: simulation.func private @unit_6.__talos_eval_body_0(
// TYPED: schedule.state.load_handle_bytes @__talos_state_value[%[[PORT]]] into %[[OLD:[0-9]+]] {state_bits = [[STATE_BITS]] : i64, width = 65 : i64}
// TYPED-NEXT: schedule.state.load_handle_bytes @__talos_state_unknown[%[[PORT]]] into %[[OLD_UNKNOWN:[0-9]+]] {state_bits = [[STATE_BITS]] : i64, width = 65 : i64}
// TYPED-NEXT: schedule.state.store_handle_bytes %{{[0-9]+}}, @__talos_state_value[%[[PORT]]] changed
// TYPED-NEXT: schedule.state.store_handle_bytes %{{[0-9]+}}, @__talos_state_unknown[%[[PORT]]] changed
// TYPED-NEXT: schedule.state.load_handle_bytes @__talos_state_value[%[[PORT]]] into %[[NEW:[0-9]+]] {state_bits = [[STATE_BITS]] : i64, width = 65 : i64}
// TYPED-NEXT: schedule.state.load_handle_bytes @__talos_state_unknown[%[[PORT]]] into %[[NEW_UNKNOWN:[0-9]+]] {state_bits = [[STATE_BITS]] : i64, width = 65 : i64}
// TYPED: schedule.transition.handle_bytes %{{[0-9]+}}, %[[PORT]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] {width = 65 : i64}

// The port is a 65-bit root at a constant offset 0: a read of 65 bits
// overlaps it from offset -64 to 64, and starts at most at bit 0 of it.
// CHECK-LABEL: func.func private @unit_2.__talos_eval_body_0(
// CHECK-NOT: llvm.call @talos_rt_v1_native_state_load_plane
// CHECK: %[[OFFSET:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[LOWER:[0-9]+]] = llvm.mlir.constant(-64 : i64) : i64
// CHECK-NEXT: %[[UPPER:[0-9]+]] = llvm.mlir.constant(64 : i64) : i64
// CHECK-NEXT: %[[IN_LOWER:[0-9]+]] = arith.cmpi sge, %[[OFFSET]], %[[LOWER]] : i64
// CHECK-NEXT: %[[IN_UPPER:[0-9]+]] = arith.cmpi sle, %[[OFFSET]], %[[UPPER]] : i64
// CHECK-NEXT: %[[OVERLAPS:[0-9]+]] = arith.andi %[[IN_LOWER]], %[[IN_UPPER]] : i1
// CHECK-NEXT: %[[SAFE_DEFAULT:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[SAFE:[0-9]+]] = arith.select %[[OVERLAPS]], %[[OFFSET]], %[[SAFE_DEFAULT]] : i64
// CHECK-NEXT: %[[ROOT_OFFSET:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[START:[0-9]+]] = arith.addi %[[SAFE]], %[[ROOT_OFFSET]] : i64
// CHECK-NEXT: %[[ZERO:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[MAX_START:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[BELOW:[0-9]+]] = arith.cmpi slt, %[[START]], %[[ZERO]] : i64
// CHECK-NEXT: %[[ABOVE:[0-9]+]] = arith.cmpi sgt, %[[START]], %[[MAX_START]] : i64
// CHECK-NEXT: %[[CLAMPED_LOW:[0-9]+]] = arith.select %[[BELOW]], %[[ZERO]], %[[START]] : i64
// CHECK-NEXT: %[[CLAMPED:[0-9]+]] = arith.select %[[ABOVE]], %[[MAX_START]], %[[CLAMPED_LOW]] : i64
// CHECK-NEXT: %[[PORT_BIT:[0-9]+]] = llvm.mlir.constant({{[0-9]+}} : i64) : i64
// CHECK-NEXT: %[[BIT:[0-9]+]] = arith.addi %[[CLAMPED]], %[[PORT_BIT]] : i64
// CHECK-NEXT: %[[THREE:[0-9]+]] = llvm.mlir.constant(3 : i64) : i64
// CHECK-NEXT: %[[BYTE:[0-9]+]] = arith.shrui %[[BIT]], %[[THREE]] : i64
// CHECK-NEXT: %[[SEVEN:[0-9]+]] = llvm.mlir.constant(7 : i64) : i64
// CHECK-NEXT: %[[BIT_IN_BYTE:[0-9]+]] = arith.andi %[[BIT]], %[[SEVEN]] : i64
// CHECK-NEXT: %[[SPAN:[0-9]+]] = schedule.state.load @__talos_state_value[%[[BYTE]]] {alignment = 1 : i64} : i72
// CHECK-NEXT: %[[SPAN_SHIFT:[0-9]+]] = llvm.zext %[[BIT_IN_BYTE]] : i64 to i72
// CHECK-NEXT: %[[SHIFTED:[0-9]+]] = arith.shrui %[[SPAN]], %[[SPAN_SHIFT]] : i72
// CHECK-NEXT: %[[LOADED:[0-9]+]] = llvm.trunc %[[SHIFTED]] : i72 to i65
// CHECK-NEXT: %[[LOW_CLIP_AMOUNT:[0-9]+]] = arith.subi %[[ZERO]], %[[START]] : i64
// CHECK-NEXT: %[[LOW_CLIP:[0-9]+]] = arith.select %[[BELOW]], %[[LOW_CLIP_AMOUNT]], %[[ZERO]] : i64
// CHECK-NEXT: %[[HIGH_CLIP_AMOUNT:[0-9]+]] = arith.subi %[[START]], %[[MAX_START]] : i64
// CHECK-NEXT: %[[HIGH_CLIP:[0-9]+]] = arith.select %[[ABOVE]], %[[HIGH_CLIP_AMOUNT]], %[[ZERO]] : i64
// CHECK-NEXT: %[[LOW_SHIFT:[0-9]+]] = llvm.zext %[[LOW_CLIP]] : i64 to i65
// CHECK-NEXT: %[[HIGH_SHIFT:[0-9]+]] = llvm.zext %[[HIGH_CLIP]] : i64 to i65
// CHECK-NEXT: %[[ALIGNED_LOW:[0-9]+]] = arith.shli %[[LOADED]], %[[LOW_SHIFT]] : i65
// CHECK-NEXT: %[[ALIGNED:[0-9]+]] = arith.shrui %[[ALIGNED_LOW]], %[[HIGH_SHIFT]] : i65
// CHECK-NEXT: %[[ALL:[^ ]+]] = arith.constant -1 : i65
// CHECK-NEXT: %[[MASK_LOW:[0-9]+]] = arith.shli %[[ALL]], %[[LOW_SHIFT]] : i65
// CHECK-NEXT: %[[MASK_IN_ROOT:[0-9]+]] = arith.shrui %[[MASK_LOW]], %[[HIGH_SHIFT]] : i65
// CHECK-NEXT: %[[NONE:[^ ]+]] = arith.constant 0 : i65
// CHECK-NEXT: %[[MASK:[0-9]+]] = arith.select %[[OVERLAPS]], %[[MASK_IN_ROOT]], %[[NONE]] : i65
// CHECK-NEXT: %[[FALLBACK:[^ ]+]] = arith.constant 0 : i65
// CHECK-NEXT: %[[KEPT:[0-9]+]] = arith.andi %[[ALIGNED]], %[[MASK]] : i65
// CHECK-NEXT: %[[OUTSIDE:[0-9]+]] = arith.xori %[[MASK]], %[[ALL]] : i65
// CHECK-NEXT: %[[FILL:[0-9]+]] = arith.andi %[[FALLBACK]], %[[OUTSIDE]] : i65
// CHECK-NEXT: %[[VALUE:[0-9]+]] = arith.ori %[[KEPT]], %[[FILL]] : i65
// CHECK-NEXT: cf.br ^{{bb[0-9]+}}(%[[VALUE]] : i65)
// The unknown plane's read is the same selection with an all-ones fallback.
// CHECK-NOT: llvm.call @talos_rt_v1_native_state_load_plane
// CHECK: %[[UNKNOWN_SPAN:[0-9]+]] = schedule.state.load @__talos_state_unknown[%{{[0-9]+}}] {alignment = 1 : i64} : i72
// CHECK: %[[UNKNOWN_ALL:[^ ]+]] = arith.constant -1 : i65
// CHECK-NEXT: %[[UNKNOWN_MASK_LOW:[0-9]+]] = arith.shli %[[UNKNOWN_ALL]], %{{[0-9]+}} : i65
// CHECK-NEXT: %[[UNKNOWN_MASK_IN_ROOT:[0-9]+]] = arith.shrui %[[UNKNOWN_MASK_LOW]], %{{[0-9]+}} : i65
// CHECK-NEXT: %[[UNKNOWN_NONE:[^ ]+]] = arith.constant 0 : i65
// CHECK-NEXT: %[[UNKNOWN_MASK:[0-9]+]] = arith.select %{{[0-9]+}}, %[[UNKNOWN_MASK_IN_ROOT]], %[[UNKNOWN_NONE]] : i65
// CHECK-NEXT: %[[UNKNOWN_FALLBACK:[^ ]+]] = arith.constant -1 : i65
// CHECK-NEXT: %[[UNKNOWN_KEPT:[0-9]+]] = arith.andi %{{[0-9]+}}, %[[UNKNOWN_MASK]] : i65
// CHECK-NEXT: %[[UNKNOWN_OUTSIDE:[0-9]+]] = arith.xori %[[UNKNOWN_MASK]], %[[UNKNOWN_ALL]] : i65
// CHECK-NEXT: %[[UNKNOWN_FILL:[0-9]+]] = arith.andi %[[UNKNOWN_FALLBACK]], %[[UNKNOWN_OUTSIDE]] : i65
// CHECK-NEXT: %[[UNKNOWN:[0-9]+]] = arith.ori %[[UNKNOWN_KEPT]], %[[UNKNOWN_FILL]] : i65
// CHECK-NEXT: cf.br ^{{bb[0-9]+}}(%[[UNKNOWN]] : i65)
// CHECK-NOT: llvm.call @talos_rt_v1_native_state_load_plane
// CHECK: return

// Each `_bytes` read stores its selection to its buffer.
// CHECK-LABEL: func.func private @unit_6.__talos_eval_body_0(
// CHECK-NOT: llvm.call @talos_rt_v1_native_state_load_plane
// CHECK: %[[OLD_VALUE:[0-9]+]] = arith.ori %{{[0-9]+}}, %{{[0-9]+}} : i65
// CHECK-NEXT: llvm.store %[[OLD_VALUE]], %[[OLD:[0-9]+]] {alignment = 1 : i64} : i65, !llvm.ptr
// CHECK: %[[OLD_UNKNOWN_VALUE:[0-9]+]] = arith.ori %{{[0-9]+}}, %{{[0-9]+}} : i65
// CHECK-NEXT: llvm.store %[[OLD_UNKNOWN_VALUE]], %[[OLD_UNKNOWN:[0-9]+]] {alignment = 1 : i64} : i65, !llvm.ptr
// CHECK: llvm.call @talos_rt_v1_native_state_store_continuous_plane(
// CHECK: llvm.call @talos_rt_v1_native_state_store_continuous_plane(
// CHECK: %[[NEW_VALUE:[0-9]+]] = arith.ori %{{[0-9]+}}, %{{[0-9]+}} : i65
// CHECK-NEXT: llvm.store %[[NEW_VALUE]], %[[NEW:[0-9]+]] {alignment = 1 : i64} : i65, !llvm.ptr
// CHECK: %[[NEW_UNKNOWN_VALUE:[0-9]+]] = arith.ori %{{[0-9]+}}, %{{[0-9]+}} : i65
// CHECK-NEXT: llvm.store %[[NEW_UNKNOWN_VALUE]], %[[NEW_UNKNOWN:[0-9]+]] {alignment = 1 : i64} : i65, !llvm.ptr
// The transition's low words are whole bytes; its high bit is an i1 load.
// CHECK-NOT: llvm.call
// CHECK: llvm.getelementptr %[[OLD]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_UNKNOWN]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: llvm.getelementptr %[[NEW]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK-NEXT: llvm.getelementptr %[[NEW_UNKNOWN]][0] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i64
// CHECK: %[[OLD_HIGH:[0-9]+]] = llvm.getelementptr %[[OLD]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: %[[OLD_BIT:[0-9]+]] = llvm.load %[[OLD_HIGH]] {alignment = 1 : i64} : !llvm.ptr -> i1
// CHECK-NEXT: llvm.zext %[[OLD_BIT]] : i1 to i64
// CHECK-NEXT: llvm.getelementptr %[[OLD_UNKNOWN]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i1
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i1 to i64
// CHECK-NEXT: llvm.getelementptr %[[NEW]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i1
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i1 to i64
// CHECK-NEXT: llvm.getelementptr %[[NEW_UNKNOWN]][8] : (!llvm.ptr) -> !llvm.ptr, i8
// CHECK-NEXT: llvm.load %{{[0-9]+}} {alignment = 1 : i64} : !llvm.ptr -> i1
// CHECK-NEXT: llvm.zext %{{[0-9]+}} : i1 to i64
