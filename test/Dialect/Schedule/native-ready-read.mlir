// RUN: talos-opt %s --pass-pipeline='builtin.module(convert-native-schedule-actions-to-llvm,llvm.func(lower-native-ready-words))' -o %t.lowered
// RUN: FileCheck %s < %t.lowered
// RUN: %llvm_dist/bin/mlir-opt %t.lowered --convert-arith-to-llvm --convert-cf-to-llvm | talos-translate --mlir-to-llvmir > %t.ll
// RUN: %llvm_dist/bin/clang -O0 %t.ll -o %t.o0
// RUN: %t.o0
// RUN: %llvm_dist/bin/clang -O3 %t.ll -o %t.o3
// RUN: %t.o3
// Local reads see ordered consume/add actions. Opaque calls see coherent leaves
// and dirty bits (the region adds only its net additions, here to the last
// leaf), and later local reads include the callback's modifications.
// CHECK-NOT: schedule.ready
// CHECK-LABEL: llvm.func @exercise
// CHECK-NOT: llvm.alloca
// CHECK: llvm.call @observe
// CHECK-NOT: schedule.ready
module {
  llvm.mlir.global internal @__talos_aot_model_ingress_v1(dense<0> : tensor<65xi64>) : !llvm.array<65 x i64>
  llvm.mlir.global internal @error(0 : i32) : i32
  llvm.func @observe() -> i1 attributes {passthrough = ["noinline"]} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %one = llvm.mlir.constant(1 : i64) : i64
    %eight = llvm.mlir.constant(8 : i64) : i64
    %high = llvm.mlir.constant(-9223372036854775808 : i64) : i64
    %first = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %end = schedule.ready.word.load @__talos_aot_model_ingress_v1[63]
    %bits = schedule.ready.word.load @__talos_aot_model_ingress_v1[64]
    %a = llvm.icmp "eq" %first, %zero : i64
    %b = llvm.icmp "eq" %end, %high : i64
    %c = llvm.icmp "eq" %bits, %high : i64
    %ab = llvm.and %a, %b : i1
    %ok = llvm.and %ab, %c : i1
    schedule.ready.word.store %eight, @__talos_aot_model_ingress_v1[0]
    schedule.ready.word.store %zero, @__talos_aot_model_ingress_v1[63]
    schedule.ready.word.store %one, @__talos_aot_model_ingress_v1[64]
    llvm.return %ok : i1
  }
  llvm.func @exercise() {
    %error = llvm.mlir.addressof @error : !llvm.ptr
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %eight = arith.constant 8 : i64
    %ten = arith.constant 10 : i64
    %high = arith.constant -9223372036854775808 : i64
    %pass = arith.constant 0 : i32
    %fail = arith.constant 1 : i32
    schedule.ready.region {
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 4096 : i64, consume = false}
      %first = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 4096 : i64}
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %one {capacity = 4096 : i64, consume = true}
      schedule.ready.update @__talos_aot_model_ingress_v1[63], %high {capacity = 4096 : i64, consume = false}
      %empty = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 4096 : i64}
      %last = schedule.ready.read @__talos_aot_model_ingress_v1[63] {capacity = 4096 : i64}
      %a = arith.cmpi eq, %first, %one : i64
      %b = arith.cmpi eq, %empty, %zero : i64
      %c = arith.cmpi eq, %last, %high : i64
      %observed = llvm.call @observe() : () -> i1
      %after = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 4096 : i64}
      schedule.ready.update @__talos_aot_model_ingress_v1[0], %two {capacity = 4096 : i64, consume = false}
      %final = schedule.ready.read @__talos_aot_model_ingress_v1[0] {capacity = 4096 : i64}
      %d = arith.cmpi eq, %after, %eight : i64
      %e = arith.cmpi eq, %final, %ten : i64
      %ab = arith.andi %a, %b : i1
      %abc = arith.andi %ab, %c : i1
      %de = arith.andi %d, %e : i1
      %readok = arith.andi %abc, %de : i1
      %ok = arith.andi %readok, %observed : i1
      %code = arith.select %ok, %pass, %fail : i32
      llvm.store %code, %error : i32, !llvm.ptr
      schedule.ready.yield
    }
    llvm.return
  }
  llvm.func @main() -> i32 {
    llvm.call @exercise() : () -> ()
    %error = llvm.mlir.addressof @error : !llvm.ptr
    %ten = llvm.mlir.constant(10 : i64) : i64
    %value = schedule.ready.word.load @__talos_aot_model_ingress_v1[0]
    %code = llvm.load %error : !llvm.ptr -> i32
    %ok = llvm.icmp "eq" %value, %ten : i64
    %fail = llvm.mlir.constant(1 : i32) : i32
    %result = llvm.select %ok, %code, %fail : i1, i32
    llvm.return %result : i32
  }
}
