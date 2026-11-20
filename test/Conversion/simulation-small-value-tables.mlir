// RUN: talos-opt %s --materialize-native-eval-transactions -o %t 2> %t.log
// RUN: FileCheck %s < %t && FileCheck %s --check-prefix=COUNT < %t.log
//
// Enumerate the value operand with a zero secondary input. The high half of
// this unsigned i3 domain must use indices 4 through 7. Preserve the original
// computation for every other secondary input.
// COUNT: talos finite value functions: tables=2
// CHECK-DAG: llvm.mlir.global internal constant @many.__talos_value_table_0(dense<[-1, -2, -3, -4, 3, 2, 1, 0]>
// CHECK-DAG: llvm.mlir.global internal constant @full.__talos_value_table_0
// CHECK-LABEL: llvm.func internal @many(
// CHECK: llvm.zext {{.*}} : i3 to i64
// CHECK: llvm.icmp "eq"
// CHECK: llvm.cond_br
// CHECK: llvm.call @round(
// CHECK: llvm.mlir.addressof @many.__talos_value_table_0
// CHECK: llvm.getelementptr
// CHECK: llvm.load
// CHECK: llvm.mlir.constant(0 : i3)
// CHECK-LABEL: llvm.func internal @full(
// CHECK-NOT: llvm.call
// CHECK: llvm.mlir.addressof @full.__talos_value_table_0
// CHECK: llvm.return
// CHECK-LABEL: llvm.func internal @reads(
// CHECK: llvm.call @full
// CHECK: llvm.load
// CHECK-LABEL: llvm.func internal @partial(
// CHECK: llvm.call @full
// CHECK: llvm.mlir.poison
// CHECK-LABEL: llvm.func internal @calls_hook(
// CHECK: llvm.call @instrumented
module attributes {native.closed_executable, native.debug_timing} {
  llvm.comdat @groups {
    llvm.comdat_selector @round any
  }
  llvm.func @unwind(...) -> i32
  llvm.func internal @round(%x: i3, %mask: i3) -> i3 comdat(@groups::@round) attributes {personality = @unwind} {
    %one = llvm.mlir.constant(1 : i3) : i3
    %two = llvm.mlir.constant(2 : i3) : i3
    %lo = llvm.shl %x, %one : i3
    %hi = llvm.lshr %x, %two : i3
    %rot = llvm.or %lo, %hi : i3
    %mix = llvm.xor %rot, %one : i3
    %v = llvm.add %mix, %mask : i3
    llvm.return %v : i3
  }
  llvm.func internal @many(%ctx: !llvm.ptr, %x: i3, %mask: i3) -> !llvm.struct<(i3, i3)> attributes {native.entry_kind = 8 : i32} {
    %s0 = llvm.call @round(%x, %mask) : (i3, i3) -> i3
    %s1 = llvm.call @round(%s0, %mask) : (i3, i3) -> i3
    %s2 = llvm.call @round(%s1, %mask) : (i3, i3) -> i3
    %s3 = llvm.call @round(%s2, %mask) : (i3, i3) -> i3
    %s4 = llvm.call @round(%s3, %mask) : (i3, i3) -> i3
    %s5 = llvm.call @round(%s4, %mask) : (i3, i3) -> i3
    %s6 = llvm.call @round(%s5, %mask) : (i3, i3) -> i3
    %s7 = llvm.call @round(%s6, %mask) : (i3, i3) -> i3
    %s8 = llvm.call @round(%s7, %mask) : (i3, i3) -> i3
    %empty = llvm.mlir.poison : !llvm.struct<(i3, i3)>
    %low = llvm.insertvalue %s8, %empty[0] : !llvm.struct<(i3, i3)>
    %all = llvm.insertvalue %mask, %low[1] : !llvm.struct<(i3, i3)>
    llvm.return %all : !llvm.struct<(i3, i3)>
  }
  llvm.func internal @full(%ctx: !llvm.ptr, %x: i3) -> i3 attributes {native.entry_kind = 8 : i32} {
    %zero = llvm.mlir.constant(0 : i3) : i3
    %v = llvm.call @many(%ctx, %x, %zero) : (!llvm.ptr, i3, i3) -> !llvm.struct<(i3, i3)>
    %low = llvm.extractvalue %v[0] : !llvm.struct<(i3, i3)>
    llvm.return %low : i3
  }
  llvm.func internal @reads(%pointer: !llvm.ptr, %x: i3) -> i3 attributes {native.entry_kind = 8 : i32} {
    %v = llvm.call @full(%pointer, %x) : (!llvm.ptr, i3) -> i3
    %m = llvm.load %pointer : !llvm.ptr -> i3
    %r = llvm.xor %v, %m : i3
    llvm.return %r : i3
  }
  llvm.func internal @partial(%pointer: !llvm.ptr, %x: i3) -> !llvm.struct<(i3, i3)> attributes {native.entry_kind = 8 : i32} {
    %v = llvm.call @full(%pointer, %x) : (!llvm.ptr, i3) -> i3
    %seed = llvm.mlir.poison : !llvm.struct<(i3, i3)>
    %r = llvm.insertvalue %v, %seed[0] : !llvm.struct<(i3, i3)>
    llvm.return %r : !llvm.struct<(i3, i3)>
  }
  llvm.func internal @instrumented(%x: i3) -> i3 attributes {instrument_function_entry = "hook"} {
    llvm.return %x : i3
  }
  llvm.func internal @calls_hook(%pointer: !llvm.ptr, %x: i3) -> i3 attributes {native.entry_kind = 8 : i32} {
    %v = llvm.call @full(%pointer, %x) : (!llvm.ptr, i3) -> i3
    %r = llvm.call @instrumented(%v) : (i3) -> i3
    llvm.return %r : i3
  }
}
