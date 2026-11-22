; REQUIRES: llvm-pass-plugin
; RUN: %llvm_dist/bin/opt -load-pass-plugin=%pass_plugin -passes=talos-clocked-guard-layout -S %s | FileCheck %s

; In a clocked kernel body (schedule.clocked_kernel), the successor of a branch
; that is not its join (its immediate post-dominator) is an arm and gets the
; unlikely edge, in either orientation, with internal control flow, and when
; arms share a tail. A diamond, an existing weight, branches whose paths only
; meet at a return, loop back edges and exit tests, and every function outside
; a clocked kernel keep their layout. The attribute decides, not the name: a
; function named like a clocked kernel body but without it keeps its layout.

; CHECK-LABEL: define i32 @kernel_body
define i32 @kernel_body(ptr %state, i1 %c0, i1 %c1, i1 %c2, i1 %c3, i1 %c4, i1 %c5, i1 %c6, i1 %c7) #0 {
entry:
  ; CHECK: br i1 %c0, label %arm0, label %join0, !prof ![[UNLIKELY_TRUE:[0-9]+]]
  br i1 %c0, label %arm0, label %join0
arm0:
  store i8 1, ptr %state
  br label %join0
join0:
  ; CHECK: br i1 %c1, label %join1, label %arm1, !prof ![[UNLIKELY_FALSE:[0-9]+]]
  br i1 %c1, label %join1, label %arm1
arm1:
  store i8 2, ptr %state
  br label %join1
join1:
  ; The arm holds a nested guard; the whole region is the arm.
  ; CHECK: br i1 %c2, label %arm2, label %join2, !prof ![[UNLIKELY_TRUE]]
  br i1 %c2, label %arm2, label %join2
arm2:
  store i8 3, ptr %state
  ; CHECK: br i1 %c3, label %arm2.nested, label %join2, !prof ![[UNLIKELY_TRUE]]
  br i1 %c3, label %arm2.nested, label %join2
arm2.nested:
  store i8 4, ptr %state
  br label %join2
join2:
  ; A diamond selects between two arms.
  ; CHECK: br i1 %c4, label %left, label %right{{$}}
  br i1 %c4, label %left, label %right
left:
  store i8 5, ptr %state
  br label %join4
right:
  store i8 6, ptr %state
  br label %join4
join4:
  ; An explicit weight is kept.
  ; CHECK: br i1 %c5, label %arm5, label %join5, !prof ![[GIVEN:[0-9]+]]
  br i1 %c5, label %arm5, label %join5, !prof !0
arm5:
  store i8 7, ptr %state
  br label %join5
join5:
  ; Both paths of %c6 meet only at %done, so neither successor is an arm. From
  ; %tail, %shared is an arm that shares its tail with the %c6 path.
  ; CHECK: br i1 %c6, label %shared, label %tail{{$}}
  br i1 %c6, label %shared, label %tail
tail:
  store i8 8, ptr %state
  ; CHECK: br i1 %c0, label %shared, label %done, !prof ![[UNLIKELY_TRUE]]
  br i1 %c0, label %shared, label %done
shared:
  store i8 9, ptr %state
  br label %done
done:
  ; A loop's back edge keeps its layout.
  ; CHECK: br i1 %c1, label %done, label %header{{$}}
  store i8 10, ptr %state
  br i1 %c1, label %done, label %header
header:
  ; The header's exit test joins at %last, outside the loop: the body
  ; continues the loop and is not an arm. Inside the body, a guard whose join
  ; is in the loop is one.
  ; CHECK: br i1 %c3, label %body, label %last{{$}}
  br i1 %c3, label %body, label %last
body:
  ; CHECK: br i1 %c4, label %inner, label %latch, !prof ![[UNLIKELY_TRUE]]
  br i1 %c4, label %inner, label %latch
inner:
  store i8 12, ptr %state
  br label %latch
latch:
  br label %header
last:
  ; The paths of %c7 meet only after both return.
  ; CHECK: br i1 %c7, label %leave, label %mid{{$}}
  br i1 %c7, label %leave, label %mid
leave:
  ret i32 1
mid:
  ; Joining only at the return, the other successor is the rest of the
  ; function rather than an arm.
  ; CHECK: br i1 %c2, label %rest, label %out{{$}}
  br i1 %c2, label %rest, label %out
rest:
  store i8 11, ptr %state
  br label %out
out:
  ret i32 0
}

; CHECK-LABEL: define i32 @__talos_clocked_9_0_0.__talos_eval_body_0
; CHECK-NOT: !prof
define i32 @__talos_clocked_9_0_0.__talos_eval_body_0(ptr %state, i1 %c0) {
entry:
  br i1 %c0, label %arm, label %join
arm:
  store i8 1, ptr %state
  br label %join
join:
  store i8 2, ptr %state
  br label %done
done:
  ret i32 0
}

attributes #0 = { "schedule.clocked_kernel" }

!0 = !{!"branch_weights", i32 7, i32 3}
; CHECK-DAG: ![[GIVEN]] = !{!"branch_weights", i32 7, i32 3}
; CHECK-DAG: ![[UNLIKELY_TRUE]] = !{!"branch_weights", i32 1, i32 1000}
; CHECK-DAG: ![[UNLIKELY_FALSE]] = !{!"branch_weights", i32 1000, i32 1}
