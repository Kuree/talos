; REQUIRES: llvm-pass-plugin
; RUN: %llvm_dist/bin/opt -load-pass-plugin=%pass_plugin -passes='function(talos-assemble-wide-integer-words)' -S %s | FileCheck %s

; A wide integer built from narrow fields is assembled by 64-bit words, in a
; portable vector. Legalizing each field of the wide integer takes time
; superlinear in its width, while every word is a native value.

target datalayout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"

; Fields fill the low word, and the rest of the vector stays zero.
; CHECK-LABEL: define i320 @aligned(
; CHECK-NOT: or i320
; CHECK-NOT: shl i320
; CHECK: bitcast <5 x i64> %{{.*}} to i320
; CHECK-NOT: or i320
define i320 @aligned(i16 %a, i16 %b, i16 %c, i16 %d) {
  %a0 = zext i16 %a to i320
  %b0 = zext i16 %b to i320
  %b1 = shl nuw i320 %b0, 16
  %c0 = zext i16 %c to i320
  %c1 = shl nuw i320 %c0, 32
  %d0 = zext i16 %d to i320
  %d1 = shl nuw i320 %d0, 48
  %x0 = or i320 %a0, %b1
  %x1 = or i320 %x0, %c1
  %x2 = or i320 %x1, %d1
  ret i320 %x2
}

; A field across a word boundary contributes to both words. The result is
; truncated to a width that is not a multiple of the word.
; CHECK-LABEL: define i300 @straddle(
; CHECK-DAG: %[[LOW:.*]] = zext i16 %a to i64
; CHECK-DAG: shl i64 %[[LOW]], 56
; CHECK-DAG: %[[HIGH:.*]] = lshr i16 %a, 8
; CHECK-DAG: zext i16 %[[HIGH]] to i64
; CHECK: bitcast <5 x i64> %{{.*}} to i320
; CHECK: trunc i320 %{{.*}} to i300
define i300 @straddle(i16 %a, i8 %b, i8 %c, i8 %d) {
  %a0 = zext i16 %a to i300
  %a1 = shl nuw i300 %a0, 56
  %b0 = zext i8 %b to i300
  %c0 = zext i8 %c to i300
  %c1 = shl nuw i300 %c0, 72
  %d0 = zext i8 %d to i300
  %d1 = shl nuw i300 %d0, 292
  %x0 = or i300 %a1, %b0
  %x1 = or i300 %x0, %c1
  %x2 = or i300 %x1, %d1
  ret i300 %x2
}

; A field wider than a word is cut into word-sized pieces. A constant field
; folds into its words: 2^128 - 256 fills the second word and most of the first.
; CHECK-LABEL: define i512 @wide_field(
; CHECK-DAG: lshr i100 %a, 34
; CHECK-DAG: trunc i100 %a to i64
; CHECK-DAG: or i64 -256,
; CHECK-DAG: or i64 -1,
; CHECK: bitcast <8 x i64> %{{.*}} to i512
define i512 @wide_field(i100 %a, i8 %b, i8 %c) {
  %a0 = zext i100 %a to i512
  %a1 = shl nuw i512 %a0, 30
  %b0 = zext i8 %b to i512
  %c0 = zext i8 %c to i512
  %c1 = shl nuw i512 %c0, 200
  %x0 = or i512 %a1, %b0
  %x1 = or i512 %x0, %c1
  %x2 = or i512 %x1, 340282366920938463463374607431768211200
  ret i512 %x2
}

; A field reaching past the top keeps only the bits the integer holds.
; CHECK-LABEL: define i264 @past_top(
; CHECK: shl i64 %{{.*}}, 4
; CHECK: bitcast <5 x i64> %{{.*}} to i320
; CHECK: trunc i320 %{{.*}} to i264
define i264 @past_top(i16 %a, i8 %b, i8 %c, i8 %d) {
  %a0 = zext i16 %a to i264
  %a1 = shl i264 %a0, 260
  %b0 = zext i8 %b to i264
  %c0 = zext i8 %c to i264
  %c1 = shl nuw i264 %c0, 8
  %d0 = zext i8 %d to i264
  %d1 = shl nuw i264 %d0, 16
  %x0 = or i264 %a1, %b0
  %x1 = or i264 %x0, %c1
  %x2 = or i264 %x1, %d1
  ret i264 %x2
}

; The offset of a variable shift is unknown, so its tree stays whole.
; CHECK-LABEL: define i320 @variable_shift(
; CHECK-NOT: x i64>
; CHECK: shl i320 %b0, %amount
; CHECK-NOT: x i64>
define i320 @variable_shift(i16 %a, i16 %b, i16 %c, i16 %d, i320 %amount) {
  %a0 = zext i16 %a to i320
  %b0 = zext i16 %b to i320
  %b1 = shl i320 %b0, %amount
  %c0 = zext i16 %c to i320
  %c1 = shl nuw i320 %c0, 32
  %d0 = zext i16 %d to i320
  %d1 = shl nuw i320 %d0, 48
  %x0 = or i320 %a0, %b1
  %x1 = or i320 %x0, %c1
  %x2 = or i320 %x1, %d1
  ret i320 %x2
}

; So does a tree with a leaf that is not a known field.
; CHECK-LABEL: define i320 @opaque_leaf(
; CHECK-NOT: x i64>
; CHECK: ret i320
define i320 @opaque_leaf(i320 %a, i16 %b, i16 %c, i16 %d) {
  %b0 = zext i16 %b to i320
  %c0 = zext i16 %c to i320
  %c1 = shl nuw i320 %c0, 32
  %d0 = zext i16 %d to i320
  %d1 = shl nuw i320 %d0, 48
  %x0 = or i320 %a, %b0
  %x1 = or i320 %x0, %c1
  %x2 = or i320 %x1, %d1
  ret i320 %x2
}

; A subtree with another user is not a field of the tree above it.
; CHECK-LABEL: define i320 @shared_subtree(
; CHECK-NOT: x i64>
; CHECK: ret i320
define i320 @shared_subtree(i16 %a, i16 %b, i16 %c, i16 %d, ptr %other) {
  %a0 = zext i16 %a to i320
  %b0 = zext i16 %b to i320
  %x0 = or i320 %a0, %b0
  store i320 %x0, ptr %other
  %c0 = zext i16 %c to i320
  %d0 = zext i16 %d to i320
  %x1 = or i320 %x0, %c0
  %x2 = or i320 %x1, %d0
  ret i320 %x2
}

; Few fields, and integers that fit the widest vector registers, legalize
; without trouble.
; CHECK-LABEL: define i320 @few_fields(
; CHECK-NOT: x i64>
; CHECK: ret i320
define i320 @few_fields(i16 %a, i16 %b, i16 %c) {
  %a0 = zext i16 %a to i320
  %b0 = zext i16 %b to i320
  %c0 = zext i16 %c to i320
  %x0 = or i320 %a0, %b0
  %x1 = or i320 %x0, %c0
  ret i320 %x1
}
; CHECK-LABEL: define i256 @narrow(
; CHECK-NOT: x i64>
; CHECK: ret i256
define i256 @narrow(i16 %a, i16 %b, i16 %c, i16 %d) {
  %a0 = zext i16 %a to i256
  %b0 = zext i16 %b to i256
  %c0 = zext i16 %c to i256
  %d0 = zext i16 %d to i256
  %x0 = or i256 %a0, %b0
  %x1 = or i256 %x0, %c0
  %x2 = or i256 %x1, %d0
  ret i256 %x2
}
