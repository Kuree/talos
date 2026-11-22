// RUN: talos-opt %s --schedule-cache-pure-cones='minimum-cost=2 maximum-cost=20' | FileCheck %s

// A pure cone helper holds code of the function it is cut from, so it keeps
// that function's origin roles (clocked_kernel, eval_body), but not
// spawn_helper, which describes only the source function itself.
// CHECK-LABEL: llvm.func internal @reader(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<clocked_kernel|eval_body|spawn_helper>
// CHECK-LABEL: llvm.func internal @reader.__talos_pure_cone(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<clocked_kernel|eval_body>,
module {
  llvm.mlir.global internal @state(0 : i64) : i64
  llvm.func internal @reader(%x: i64) -> i64 attributes {schedule.eval.role = #schedule.eval_role<clocked_kernel|eval_body|spawn_helper>} {
    %p = llvm.mlir.addressof @state : !llvm.ptr
    %s = llvm.load %p : !llvm.ptr -> i64
    %a = arith.addi %x, %s : i64
    %b = arith.xori %a, %s : i64
    llvm.return %b : i64
  }
  llvm.func @main(%x: i64) -> i64 {
    %a = llvm.call @reader(%x) : (i64) -> i64
    %b = llvm.call @reader(%x) : (i64) -> i64
    %c = arith.addi %a, %b : i64
    llvm.return %c : i64
  }
}
