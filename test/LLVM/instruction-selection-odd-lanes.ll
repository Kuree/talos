; REQUIRES: llvm-pass-plugin
; RUN: %llvm_dist/bin/opt -load-pass-plugin=%pass_plugin -passes='function(talos-print-instruction-selection)' -disable-output %s 2>&1 | FileCheck %s

; Code generation selects most functions with GlobalISel. Integer vectors with
; lanes other than i1/i8/i16/i32/i64, as the SLP vectorizer forms from shifts
; and extracts of an odd-width value, use SelectionDAG in bounded functions, as
; outlined clocked update groups do. Sub-byte lanes use it at any size: AArch64
; GlobalISel's legalizer does not terminate on a bitcast between a 64-bit
; vector and <16 x i4> (a 163-instruction BlackParrot eval group needed over
; 8 GB before it was killed).

; CHECK: talos-isel: odd_lanes selection-dag
define void @odd_lanes(ptr %p, ptr %q) {
  %v = load i72, ptr %p, align 1
  %a = insertelement <8 x i72> poison, i72 %v, i64 0
  %s = shufflevector <8 x i72> %a, <8 x i72> poison, <8 x i32> zeroinitializer
  %r = lshr <8 x i72> %s, <i72 22, i72 23, i72 24, i72 25, i72 26, i72 27, i72 28, i72 29>
  %t = trunc <8 x i72> %r to <8 x i8>
  store <8 x i8> %t, ptr %q, align 1
  ret void
}

; CHECK: talos-isel: nibble_lanes selection-dag
define i4 @nibble_lanes(<8 x i8> %v) {
  %n = bitcast <8 x i8> %v to <16 x i4>
  %e = extractelement <16 x i4> %n, i64 3
  ret i4 %e
}

; CHECK: talos-isel: crumb_lanes selection-dag
define <8 x i2> @crumb_lanes(<8 x i2> %a, <8 x i2> %b) {
  %s = add <8 x i2> %a, %b
  ret <8 x i2> %s
}

; CHECK: talos-isel: native_lanes global-isel
define <4 x i32> @native_lanes(<4 x i32> %a, <4 x i32> %b) {
  %s = add <4 x i32> %a, %b
  ret <4 x i32> %s
}

; CHECK: talos-isel: mask_lanes global-isel
define <2 x i1> @mask_lanes(<2 x i64> %a, <2 x i64> %b) {
  %c = icmp eq <2 x i64> %a, %b
  ret <2 x i1> %c
}

; A scalar odd-width integer is not a vector lane.
; CHECK: talos-isel: scalar_odd global-isel
define i72 @scalar_odd(i72 %a, i72 %b) {
  %s = add i72 %a, %b
  ret i72 %s
}

; CHECK: talos-isel: clocked_group selection-dag
define void @clocked_group(ptr %p) #0 {
  store i8 1, ptr %p, align 1
  ret void
}

attributes #0 = { "talos.clocked-update-group" }
