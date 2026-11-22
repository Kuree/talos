// RUN: talos -emit-slang %s | talos-opt --test-talos-native-backend='scheduler=eval stop-after=materialize' | FileCheck %s --implicit-check-not=schedule.state.load_handle --implicit-check-not=schedule.state.store_handle

// The register reads a field of a dynamically indexed element of an array
// that the initial block forces, so its generated eval body reads the field
// behind the static specialization guard through the handle
// offset(guard(offset(root, index * stride), valid), field position). AOT
// planning folds the chain down to its constant root: it sums the offsets and
// requires the guard's validity in the overlap condition, so an invalid index
// reads the value of an invalid index in every bit, 0 in the value plane and
// 1 in the unknown plane (IEEE 1800-2023 7.4.5, 11.5.1). The array is three
// 68-bit elements at a 128-bit stride: a 65-bit read overlaps the 384-bit root
// from offset -64 to 383.
// The two-state variant reads no unknown plane, but an invalid index still
// selects the all-ones unknown fallback.
// The input is SystemVerilog because the guarded root and the selection
// chain come from native planning of a forced root.
module top;
  typedef struct packed { logic [64:0] hi; logic [2:0] lo; } entry_t;
  logic clk = 0;
  entry_t data [3] = '{default: '0};
  logic [1:0] idx = 1;
  logic [64:0] q;
  always_ff @(posedge clk) q <= data[idx].hi;
  always #5 clk = ~clk;
  initial begin
    #6 force data = '{default: '1};
    #10 release data;
  end
endmodule

// CHECK-LABEL: func.func private @unit_3.__talos_eval_body_0(
// CHECK: %[[INVALID:[^ ]+]] = arith.constant -1 : i64
// CHECK-NEXT: %[[NOT_INVALID:[0-9]+]] = arith.cmpi ne, %{{[^ ]+}}, %[[INVALID]] : i64
// CHECK-NEXT: %[[VALID:[0-9]+]] = arith.andi %{{[0-9]+}}, %[[NOT_INVALID]] : i1
// CHECK-NEXT: %[[STRIDE:[^ ]+]] = arith.constant 128 : i64
// CHECK-NEXT: %[[ELEMENT:[0-9]+]] = arith.muli %{{[0-9]+}}, %[[STRIDE]] : i64
// CHECK: %[[FIELD:[^ ]+]] = arith.constant 3 : i64
// CHECK: %[[OFFSET:[0-9]+]] = arith.addi %[[ELEMENT]], %[[FIELD]] : i64
// CHECK-NEXT: %[[LOWER:[0-9]+]] = llvm.mlir.constant(-64 : i64) : i64
// CHECK-NEXT: %[[UPPER:[0-9]+]] = llvm.mlir.constant(383 : i64) : i64
// CHECK-NEXT: %[[IN_LOWER:[0-9]+]] = arith.cmpi sge, %[[OFFSET]], %[[LOWER]] : i64
// CHECK-NEXT: %[[IN_UPPER:[0-9]+]] = arith.cmpi sle, %[[OFFSET]], %[[UPPER]] : i64
// CHECK-NEXT: %[[IN_ROOT:[0-9]+]] = arith.andi %[[IN_LOWER]], %[[IN_UPPER]] : i1
// CHECK-NEXT: %[[OVERLAPS:[0-9]+]] = arith.andi %[[VALID]], %[[IN_ROOT]] : i1
// CHECK-NEXT: %[[SAFE_DEFAULT:[0-9]+]] = llvm.mlir.constant(0 : i64) : i64
// CHECK-NEXT: %[[SAFE:[0-9]+]] = arith.select %[[OVERLAPS]], %[[OFFSET]], %[[SAFE_DEFAULT]] : i64
// CHECK: schedule.state.load @__talos_state_value[%{{[0-9]+}}] {alignment = 1 : i64} : i72
// CHECK: %[[ALIGNED:[0-9]+]] = arith.shrui %{{[0-9]+}}, %[[HIGH_SHIFT:[0-9]+]] : i65
// CHECK-NEXT: %[[ALL:[^ ]+]] = arith.constant -1 : i65
// CHECK-NEXT: %[[MASK_LOW:[0-9]+]] = arith.shli %[[ALL]], %{{[0-9]+}} : i65
// CHECK-NEXT: %[[MASK_IN_ROOT:[0-9]+]] = arith.shrui %[[MASK_LOW]], %[[HIGH_SHIFT]] : i65
// CHECK-NEXT: %[[NONE:[^ ]+]] = arith.constant 0 : i65
// CHECK-NEXT: %[[MASK:[0-9]+]] = arith.select %[[OVERLAPS]], %[[MASK_IN_ROOT]], %[[NONE]] : i65
// CHECK-NEXT: %[[FALLBACK:[^ ]+]] = arith.constant 0 : i65
// CHECK-NEXT: %[[KEPT:[0-9]+]] = arith.andi %[[ALIGNED]], %[[MASK]] : i65
// CHECK-NEXT: %[[OUTSIDE:[0-9]+]] = arith.xori %[[MASK]], %[[ALL]] : i65
// CHECK-NEXT: %[[FILL:[0-9]+]] = arith.andi %[[FALLBACK]], %[[OUTSIDE]] : i65
// CHECK-NEXT: arith.ori %[[KEPT]], %[[FILL]] : i65
// CHECK: arith.addi %[[ELEMENT]], %[[FIELD]] : i64
// CHECK: %[[UNKNOWN_IN_ROOT:[0-9]+]] = arith.andi %{{[0-9]+}}, %{{[0-9]+}} : i1
// CHECK-NEXT: %[[UNKNOWN_OVERLAPS:[0-9]+]] = arith.andi %[[VALID]], %[[UNKNOWN_IN_ROOT]] : i1
// CHECK: schedule.state.load @__talos_state_unknown[%{{[0-9]+}}] {alignment = 1 : i64} : i72
// CHECK: %[[UNKNOWN_MASK:[0-9]+]] = arith.select %[[UNKNOWN_OVERLAPS]], %{{[0-9]+}}, %{{[^ ]+}} : i65
// CHECK-NEXT: %[[UNKNOWN_FALLBACK:[^ ]+]] = arith.constant -1 : i65
// CHECK-NEXT: arith.andi %{{[0-9]+}}, %[[UNKNOWN_MASK]] : i65
// CHECK-NEXT: %[[UNKNOWN_OUTSIDE:[0-9]+]] = arith.xori %[[UNKNOWN_MASK]], %{{[^ ]+}} : i65
// CHECK-NEXT: arith.andi %[[UNKNOWN_FALLBACK]], %[[UNKNOWN_OUTSIDE]] : i65
// CHECK: return

// CHECK-LABEL: func.func private @unit_3.__talos_eval_body_0.__talos_two_state_0(
// CHECK: %[[TWO_STATE_INVALID:[^ ]+]] = arith.constant -1 : i64
// CHECK-NEXT: %[[TWO_STATE_NOT_INVALID:[0-9]+]] = arith.cmpi ne, %{{[^ ]+}}, %[[TWO_STATE_INVALID]] : i64
// CHECK-NEXT: %[[TWO_STATE_VALID:[0-9]+]] = arith.andi %{{[0-9]+}}, %[[TWO_STATE_NOT_INVALID]] : i1
// CHECK-NEXT: %[[TWO_STATE_STRIDE:[^ ]+]] = arith.constant 128 : i64
// CHECK-NEXT: %[[TWO_STATE_ELEMENT:[0-9]+]] = arith.muli %{{[0-9]+}}, %[[TWO_STATE_STRIDE]] : i64
// CHECK: schedule.state.load @__talos_state_value[%{{[0-9]+}}] {alignment = 1 : i64} : i72
// The unknown plane's selection, after the value plane's:
// CHECK: arith.addi %[[TWO_STATE_ELEMENT]], %{{[^ ]+}} : i64
// CHECK: %[[TWO_STATE_IN_ROOT:[0-9]+]] = arith.andi %{{[0-9]+}}, %{{[0-9]+}} : i1
// CHECK-NEXT: %[[TWO_STATE_OVERLAPS:[0-9]+]] = arith.andi %[[TWO_STATE_VALID]], %[[TWO_STATE_IN_ROOT]] : i1
// CHECK-NOT: schedule.state.load
// CHECK: %[[NO_UNKNOWN:[^ ]+]] = arith.constant 0 : i65
// CHECK-NOT: schedule.state.load
// CHECK: arith.shli %[[NO_UNKNOWN]], %{{[0-9]+}} : i65
// CHECK: %[[TWO_STATE_MASK:[0-9]+]] = arith.select %[[TWO_STATE_OVERLAPS]], %{{[0-9]+}}, %{{[^ ]+}} : i65
// CHECK-NEXT: %[[TWO_STATE_FALLBACK:[^ ]+]] = arith.constant -1 : i65
// CHECK-NEXT: arith.andi %{{[0-9]+}}, %[[TWO_STATE_MASK]] : i65
// CHECK-NEXT: %[[TWO_STATE_OUTSIDE:[0-9]+]] = arith.xori %[[TWO_STATE_MASK]], %{{[^ ]+}} : i65
// CHECK-NEXT: arith.andi %[[TWO_STATE_FALLBACK]], %[[TWO_STATE_OUTSIDE]] : i65
// CHECK: return
