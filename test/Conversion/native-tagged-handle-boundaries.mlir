// RUN: talos-opt %s --test-talos-lower-native-handle-ops | mlir-opt --convert-arith-to-llvm | mlir-runner -e main -entry-point-result=i32 | FileCheck %s
// CHECK: {{^0$}}

// Negative offsets are representable so partially overlapping part-selects
// retain their valid bits (11.5.1). Unrepresentable selections stay invalid
// even if a subsequent selection would bring the offset back into range.
module {
  llvm.func @static(%first: i64, %second: i64, %valid: i1) -> i64 {
    %root = arith.constant 0x4000000200000000 : i64
    %a = schedule.handle.offset %root, %first
    %g = schedule.handle.guard %valid, %a
    %b = schedule.handle.offset %g, %second
    llvm.return %b : i64
  }
  llvm.func @automatic(%delta: i64) -> i64 {
    %root = arith.constant 0x80000002FFFFFFFF : i64
    %a = schedule.handle.offset %root, %delta
    llvm.return %a : i64
  }
  llvm.func @main() -> i32 {
    %on = arith.constant true
    %off = arith.constant false
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %minus_one = arith.constant -1 : i64
    %min = arith.constant -2147483648 : i64
    %max = arith.constant 2147483647 : i64
    %large = arith.constant 2147483648 : i64
    %smin = arith.constant 0x8000000000000000 : i64
    %smax = arith.constant 0x7FFFFFFFFFFFFFFF : i64
    %expected_min = arith.constant 0x4000000280000000 : i64
    %expected_max = arith.constant 0x400000027FFFFFFF : i64
    %expected_auto = arith.constant 0x8000000200000000 : i64
    %a = llvm.call @static(%min, %zero, %on) : (i64, i64, i1) -> i64
    %b = llvm.call @static(%max, %zero, %on) : (i64, i64, i1) -> i64
    %c = llvm.call @static(%large, %minus_one, %on) : (i64, i64, i1) -> i64
    %d = llvm.call @static(%min, %smin, %on) : (i64, i64, i1) -> i64
    %e = llvm.call @static(%max, %smax, %on) : (i64, i64, i1) -> i64
    %f = llvm.call @static(%zero, %one, %off) : (i64, i64, i1) -> i64
    %g = llvm.call @automatic(%one) : (i64) -> i64
    %p0 = llvm.icmp "ne" %a, %expected_min : i64
    %p1 = llvm.icmp "ne" %b, %expected_max : i64
    %p2 = llvm.icmp "ne" %c, %minus_one : i64
    %p3 = llvm.icmp "ne" %d, %minus_one : i64
    %p4 = llvm.icmp "ne" %e, %minus_one : i64
    %p5 = llvm.icmp "ne" %f, %minus_one : i64
    %p6 = llvm.icmp "ne" %g, %expected_auto : i64
    %v0 = llvm.or %p0, %p1 : i1
    %v1 = llvm.or %p2, %p3 : i1
    %v2 = llvm.or %p4, %p5 : i1
    %v3 = llvm.or %v0, %v1 : i1
    %v4 = llvm.or %v2, %p6 : i1
    %bad = llvm.or %v3, %v4 : i1
    %result = llvm.zext %bad : i1 to i32
    llvm.return %result : i32
  }
}
