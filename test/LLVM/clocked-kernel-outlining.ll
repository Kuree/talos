; REQUIRES: llvm-pass-plugin
; RUN: %llvm_dist/bin/opt -load-pass-plugin=%pass_plugin -passes='talos-outline-clocked-kernels<8>' -verify-each -S %s -o %t.ll
; RUN: FileCheck %s < %t.ll
; RUN: %llvm_dist/bin/lli %s
; RUN: %llvm_dist/bin/lli %t.ll
; RUN: %llvm_dist/bin/opt -load-pass-plugin=%pass_plugin -passes='talos-outline-clocked-kernels<8>,talos-outline-clocked-kernels<8>' -verify-each -disable-output %s

; Extraction must retain a sampled value across a call that changes its source,
; preserve early exits, and rematerialize chained addresses in dependency order.
; The small explicit threshold exercises the same selection as large kernels.

@state = internal global [8 x i64] zeroinitializer
@sample = internal global i64 11

define internal void @change_sample() noinline {
  store i64 99, ptr @sample
  ret void
}

; CHECK-LABEL: define i32 @__talos_clocked_test.__talos_eval_body_0(
; CHECK-NOT: alloca
; CHECK: %sampled = load i64, ptr @sample
; CHECK-NOT: alloca
; CHECK: call fastcc {{.*}}@__talos_clocked_test.__talos_eval_body_0.__talos_update_group
; CHECK-NOT: alloca
; CHECK: ret i32
define i32 @__talos_clocked_test.__talos_eval_body_0(ptr %base, i1 %fail) {
entry:
  %sampled = load i64, ptr @sample
  %middle = getelementptr i64, ptr %base, i64 1
  %field = getelementptr i64, ptr %middle, i64 1
  br label %first
first:
  call void @change_sample()
  %a0 = add i64 %sampled, 1
  store volatile i64 %a0, ptr %base
  %a1 = add i64 %sampled, 2
  store volatile i64 %a1, ptr %middle
  %a2 = add i64 %sampled, 3
  store volatile i64 %a2, ptr %field
  br label %second
second:
  %b0 = load volatile i64, ptr %base
  %b1 = add i64 %b0, 10
  store volatile i64 %b1, ptr %base
  %b2 = load volatile i64, ptr %field
  %b3 = add i64 %b2, %sampled
  store volatile i64 %b3, ptr %field
  store volatile i64 %sampled, ptr %middle
  br label %third
third:
  %c0 = load volatile i64, ptr %base
  %c1 = add i64 %c0, 10
  store volatile i64 %c1, ptr %base
  %c2 = load volatile i64, ptr %middle
  %c3 = add i64 %c2, %sampled
  store volatile i64 %c3, ptr %middle
  store volatile i64 %sampled, ptr %field
  br i1 %fail, label %error, label %fourth
fourth:
  %d0 = load volatile i64, ptr %base
  %d1 = add i64 %d0, 10
  store volatile i64 %d1, ptr %base
  %d2 = load volatile i64, ptr %middle
  %d3 = add i64 %d2, %sampled
  store volatile i64 %d3, ptr %middle
  store volatile i64 %sampled, ptr %field
  br label %done
error:
  ret i32 7
done:
  ret i32 0
}

; A live scalar result must stay in the caller, without an output slot.
; CHECK-LABEL: define void @__talos_clocked_live.__talos_eval_body_0(
; CHECK-NOT: call
; CHECK: ret void
define void @__talos_clocked_live.__talos_eval_body_0(ptr %p, i64 %x) {
entry:
  br label %first
first:
  %a0 = add i64 %x, 1
  store volatile i64 %a0, ptr %p
  %a1 = add i64 %a0, 1
  store volatile i64 %a1, ptr %p
  %a2 = add i64 %a1, 1
  store volatile i64 %a2, ptr %p
  %a3 = add i64 %a2, 1
  store volatile i64 %a3, ptr %p
  br label %second
second:
  %b0 = add i64 %a3, 1
  store volatile i64 %b0, ptr %p
  %b1 = add i64 %b0, 1
  store volatile i64 %b1, ptr %p
  %b2 = add i64 %b1, 1
  store volatile i64 %b2, ptr %p
  %b3 = add i64 %b2, 1
  store volatile i64 %b3, ptr %p
  br label %third
third:
  %c0 = add i64 %b3, 1
  store volatile i64 %c0, ptr %p
  %c1 = add i64 %c0, 1
  store volatile i64 %c1, ptr %p
  %c2 = add i64 %c1, 1
  store volatile i64 %c2, ptr %p
  %c3 = add i64 %c2, 1
  store volatile i64 %c3, ptr %p
  br label %done
done:
  %d0 = add i64 %c3, 1
  store volatile i64 %d0, ptr %p
  %d1 = add i64 %d0, 1
  store volatile i64 %d1, ptr %p
  %d2 = add i64 %d1, 1
  store volatile i64 %d2, ptr %p
  %d3 = add i64 %d2, 1
  store volatile i64 %d3, ptr %p
  ret void
}

; Wide live-ins need scalar legalization and are unsuitable helper arguments.
; CHECK-LABEL: define void @__talos_clocked_wide.__talos_eval_body_0(
; CHECK-NOT: call
; CHECK: ret void
define void @__talos_clocked_wide.__talos_eval_body_0(ptr %p, i128 %wide) {
entry:
  br label %first
first:
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  br label %second
second:
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  br label %third
third:
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  br label %done
done:
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  store volatile i128 %wide, ptr %p
  ret void
}

; Returning a computed value must not create an implicit output stack slot.
; CHECK-LABEL: define i64 @__talos_clocked_return.__talos_eval_body_0(
; CHECK-NOT: alloca
; CHECK: %value = load volatile i64, ptr %p
; CHECK-NOT: alloca
; CHECK: ret i64 %result
define i64 @__talos_clocked_return.__talos_eval_body_0(ptr %p) {
entry:
  br label %first
first:
  store volatile i64 0, ptr %p
  store volatile i64 1, ptr %p
  store volatile i64 2, ptr %p
  store volatile i64 3, ptr %p
  store volatile i64 4, ptr %p
  store volatile i64 5, ptr %p
  store volatile i64 6, ptr %p
  store volatile i64 7, ptr %p
  br label %second
second:
  store volatile i64 0, ptr %p
  store volatile i64 1, ptr %p
  store volatile i64 2, ptr %p
  store volatile i64 3, ptr %p
  store volatile i64 4, ptr %p
  store volatile i64 5, ptr %p
  store volatile i64 6, ptr %p
  store volatile i64 7, ptr %p
  br label %third
third:
  store volatile i64 0, ptr %p
  store volatile i64 1, ptr %p
  store volatile i64 2, ptr %p
  store volatile i64 3, ptr %p
  store volatile i64 4, ptr %p
  store volatile i64 5, ptr %p
  store volatile i64 6, ptr %p
  store volatile i64 7, ptr %p
  br label %fourth
fourth:
  store volatile i64 0, ptr %p
  store volatile i64 1, ptr %p
  store volatile i64 2, ptr %p
  store volatile i64 3, ptr %p
  store volatile i64 4, ptr %p
  store volatile i64 5, ptr %p
  store volatile i64 6, ptr %p
  store volatile i64 7, ptr %p
  %value = load volatile i64, ptr %p
  %result = add i64 %value, 3
  ret i64 %result
}

define i32 @main() {
  store i64 11, ptr @sample
  %ok = call i32 @__talos_clocked_test.__talos_eval_body_0(ptr @state, i1 false)
  %a = load i64, ptr @state
  %b = load i64, ptr getelementptr ([8 x i64], ptr @state, i64 0, i64 1)
  %c = load i64, ptr getelementptr ([8 x i64], ptr @state, i64 0, i64 2)
  %ca = icmp eq i64 %a, 42
  %cb = icmp eq i64 %b, 33
  %cc = icmp eq i64 %c, 11
  %cs = icmp eq i32 %ok, 0
  %ab = and i1 %ca, %cb
  %cscc = and i1 %cc, %cs
  %success = and i1 %ab, %cscc
  store i64 11, ptr @sample
  %err = call i32 @__talos_clocked_test.__talos_eval_body_0(ptr @state, i1 true)
  %e = load i64, ptr @state
  %ce = icmp eq i64 %e, 32
  %cerr = icmp eq i32 %err, 7
  %early = and i1 %ce, %cerr
  %all = and i1 %success, %early
  %returned = call i64 @__talos_clocked_return.__talos_eval_body_0(ptr @state)
  %return_ok = icmp eq i64 %returned, 10
  %all_ok = and i1 %all, %return_ok
  %result = select i1 %all_ok, i32 0, i32 1
  ret i32 %result
}

; CHECK-LABEL: define internal fastcc void @__talos_clocked_test.__talos_eval_body_0.__talos_update_group(
; CHECK: getelementptr i8, ptr {{.*}}, i64 8
; CHECK: getelementptr i8, ptr {{.*}}, i64 16
; CHECK: call void @change_sample()
; CHECK-NOT: load i64, ptr @sample
