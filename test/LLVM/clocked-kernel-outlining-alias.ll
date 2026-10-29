; REQUIRES: llvm-pass-plugin
; RUN: %llvm_dist/bin/opt -load-pass-plugin=%pass_plugin -passes='talos-outline-clocked-kernels<8>' -verify-each -S %s -o %t.ll
; RUN: FileCheck %s < %t.ll
; RUN: %llvm_dist/bin/lli %s
; RUN: %llvm_dist/bin/lli %t.ll

@values = internal global i64 0
@unknown = internal global i64 0

declare void @llvm.assume(i1)

; CHECK-LABEL: define void @__talos_clocked_alias.__talos_eval_body_0(
; CHECK: call fastcc void @__talos_clocked_alias.__talos_eval_body_0.__talos_update_group
define void @__talos_clocked_alias.__talos_eval_body_0(ptr %a, ptr %b) {
entry:
  call void @llvm.assume(i1 true) [ "separate_storage"(ptr %a, ptr %b) ]
  br label %first
first:
  store volatile i64 1, ptr %a
  store volatile i64 2, ptr %b
  store volatile i64 1, ptr %a
  store volatile i64 2, ptr %b
  store volatile i64 1, ptr %a
  store volatile i64 2, ptr %b
  store volatile i64 1, ptr %a
  store volatile i64 2, ptr %b
  br label %second
second:
  store volatile i64 3, ptr %a
  store volatile i64 4, ptr %b
  store volatile i64 3, ptr %a
  store volatile i64 4, ptr %b
  store volatile i64 3, ptr %a
  store volatile i64 4, ptr %b
  store volatile i64 3, ptr %a
  store volatile i64 4, ptr %b
  br label %third
third:
  store volatile i64 5, ptr %a
  store volatile i64 6, ptr %b
  store volatile i64 5, ptr %a
  store volatile i64 6, ptr %b
  store volatile i64 5, ptr %a
  store volatile i64 6, ptr %b
  store volatile i64 5, ptr %a
  store volatile i64 6, ptr %b
  br label %done
done:
  store volatile i64 7, ptr %a
  store volatile i64 8, ptr %b
  store volatile i64 7, ptr %a
  store volatile i64 8, ptr %b
  store volatile i64 7, ptr %a
  store volatile i64 8, ptr %b
  store volatile i64 7, ptr %a
  store volatile i64 8, ptr %b
  ret void
}

define i32 @main() {
  call void @__talos_clocked_alias.__talos_eval_body_0(ptr @values, ptr @unknown)
  %a = load i64, ptr @values
  %b = load i64, ptr @unknown
  %a_ok = icmp eq i64 %a, 7
  %b_ok = icmp eq i64 %b, 8
  %ok = and i1 %a_ok, %b_ok
  %status = select i1 %ok, i32 0, i32 1
  ret i32 %status
}

; CHECK-LABEL: define internal fastcc void @__talos_clocked_alias.__talos_eval_body_0.__talos_update_group(
; CHECK: call void @llvm.assume(i1 true) [ "separate_storage"(ptr %a, ptr %b) ]
; CHECK: store volatile i64 1, ptr %a
; CHECK: store volatile i64 2, ptr %b
; CHECK: "talos.clocked-update-group"
