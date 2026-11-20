// RUN: talos-opt %s --materialize-native-eval-transactions -o %t.mlir 2> %t.log
// RUN: FileCheck %s --check-prefix=COUNT < %t.log && FileCheck %s < %t.mlir

// A polynomial step is called from another native partition with two
// repeated literal polynomials and one dynamic polynomial. The dynamic
// data and unknown-mask arguments retain their original values on all paths.
// COUNT: talos constant value functions: copies=2 calls=4
// CHECK-LABEL: llvm.func internal @step.__talos_const
// CHECK: llvm.mlir.constant(29 : i8)
// CHECK: llvm.mlir.poison
// CHECK: llvm.insertvalue %arg2, %{{.*}}[1]
// CHECK-LABEL: llvm.func internal @step.__talos_const
// CHECK: llvm.mlir.constant(27 : i8)
// CHECK: llvm.mlir.poison
// CHECK: llvm.insertvalue %arg2, %{{.*}}[1]
// CHECK-LABEL: llvm.func @caller
// CHECK: llvm.call @[[A:step.__talos_const[^ (]*]]
// CHECK: llvm.call @[[A]](
// CHECK: llvm.call @[[B:step.__talos_const[^ (]*]]
// CHECK: llvm.call @[[B]](
// CHECK: llvm.call @step(

module attributes {native.closed_executable, native.debug_timing} {
  llvm.func @step(%in: i8, %poly: i8, %mask: i8) -> i8 attributes {native.entry_kind = 8 : i32, native.partition = "operator", sym_visibility = "private"} {
    %zero = llvm.mlir.constant(0 : i8) : i8
    %one = llvm.mlir.constant(1 : i8) : i8
    %carry0 = llvm.icmp "slt" %in, %zero : i8
    %shift0 = llvm.shl %in, %one : i8
    %tap0 = llvm.select %carry0, %poly, %zero : i1, i8
    %v0 = llvm.xor %shift0, %tap0 : i8
    %carry1 = llvm.icmp "slt" %v0, %zero : i8
    %shift1 = llvm.shl %v0, %one : i8
    %tap1 = llvm.select %carry1, %poly, %zero : i1, i8
    %v1 = llvm.xor %shift1, %tap1 : i8
    %carry2 = llvm.icmp "slt" %v1, %zero : i8
    %shift2 = llvm.shl %v1, %one : i8
    %tap2 = llvm.select %carry2, %poly, %zero : i1, i8
    %v2 = llvm.xor %shift2, %tap2 : i8
    %carry3 = llvm.icmp "slt" %v2, %zero : i8
    %shift3 = llvm.shl %v2, %one : i8
    %tap3 = llvm.select %carry3, %poly, %zero : i1, i8
    %v3 = llvm.xor %shift3, %tap3 : i8
    %carry4 = llvm.icmp "slt" %v3, %zero : i8
    %shift4 = llvm.shl %v3, %one : i8
    %tap4 = llvm.select %carry4, %poly, %zero : i1, i8
    %v4 = llvm.xor %shift4, %tap4 : i8
    %carry5 = llvm.icmp "slt" %v4, %zero : i8
    %shift5 = llvm.shl %v4, %one : i8
    %tap5 = llvm.select %carry5, %poly, %zero : i1, i8
    %v5 = llvm.xor %shift5, %tap5 : i8
    %carry6 = llvm.icmp "slt" %v5, %zero : i8
    %shift6 = llvm.shl %v5, %one : i8
    %tap6 = llvm.select %carry6, %poly, %zero : i1, i8
    %v6 = llvm.xor %shift6, %tap6 : i8
    %carry7 = llvm.icmp "slt" %v6, %zero : i8
    %shift7 = llvm.shl %v6, %one : i8
    %tap7 = llvm.select %carry7, %poly, %zero : i1, i8
    %v7 = llvm.xor %shift7, %tap7 : i8
    %empty = llvm.mlir.poison : !llvm.struct<(i8, i8)>
    %first = llvm.insertvalue %v7, %empty[0] : !llvm.struct<(i8, i8)>
    %pair = llvm.insertvalue %mask, %first[1] : !llvm.struct<(i8, i8)>
    %value = llvm.extractvalue %pair[0] : !llvm.struct<(i8, i8)>
    %x = llvm.extractvalue %pair[1] : !llvm.struct<(i8, i8)>
    %r = llvm.xor %value, %x : i8
    llvm.return %r : i8
  }
  llvm.func @caller(%a: i8, %b: i8, %poly: i8, %mask: i8) -> i8 attributes {native.partition = "users"} {
    %p = llvm.mlir.constant(27 : i8) : i8
    %q = llvm.mlir.constant(29 : i8) : i8
    %p0 = llvm.call @step(%a, %p, %mask) : (i8, i8, i8) -> i8
    %p1 = llvm.call @step(%b, %p, %mask) : (i8, i8, i8) -> i8
    %q0 = llvm.call @step(%a, %q, %mask) : (i8, i8, i8) -> i8
    %q1 = llvm.call @step(%b, %q, %mask) : (i8, i8, i8) -> i8
    %d = llvm.call @step(%a, %poly, %mask) : (i8, i8, i8) -> i8
    %p2 = llvm.xor %p0, %p1 : i8
    %q2 = llvm.xor %q0, %q1 : i8
    %pq = llvm.add %p2, %q2 : i8
    %ret = llvm.xor %pq, %d : i8
    llvm.return %ret : i8
  }
}
