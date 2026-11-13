// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s
// RUN: talos-opt %s '--test-talos-set-module-attributes=attrs="{native.max_state_domain_functions = 0 : i64}"' --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=NO-PROOF

// Packed lowering keeps the two-plane ABI of a block argument the
// whole-design proof shows two-state, and replaces its unknown plane with a
// zero, so no X/Z test reads it: the entry argument (both callers pass known
// values) and a joined argument (both edges pass two-state values).
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @two_state_block_arguments {
    simulation.code_unit.decl 80 in 0 function hierarchy "top.truth"
    simulation.code_unit.decl 81 in 0 initial hierarchy "top.root"
    simulation.scope.decl 0 hierarchy "top"
    simulation.storage.decl 0 in 0 : i1 design hierarchy "top.a"
    simulation.storage.decl 1 in 0 : i1 design hierarchy "top.b"

    simulation.func private @truth(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %pick: i1 {simulation.capture_kind = 1 : i32},
        %value: !simulation.logic<8> {simulation.capture_kind = 1 : i32})
        -> i1 attributes {code_unit_id = 80 : i64, entry_kind = 8 : i32} {
      %entry_truth = simulation.logic.is_true %value : !simulation.logic<8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      %bumped = simulation.logic.binary add %value, %one : !simulation.logic<8>
      cf.cond_br %pick, ^join(%value : !simulation.logic<8>),
                        ^join(%bumped : !simulation.logic<8>)
    ^join(%joined: !simulation.logic<8>):
      %join_truth = simulation.logic.is_true %joined : !simulation.logic<8>
      %both = arith.andi %entry_truth, %join_truth : i1
      simulation.return %both : i1
    }

    simulation.func @root(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 81 : i64, entry_kind = 1 : i32} {
      %true = arith.constant true
      %false = arith.constant false
      %first = simulation.logic.constant 41 : i8, 0 : i8 :
          !simulation.logic<8>
      %second = simulation.logic.constant 7 : i8, 0 : i8 :
          !simulation.logic<8>
      %a = simulation.call @truth(%ctx, %true, %first) :
          (!simulation.context, i1, !simulation.logic<8>) -> i1
      %b = simulation.call @truth(%ctx, %false, %second) :
          (!simulation.context, i1, !simulation.logic<8>) -> i1
      %a_ref = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      simulation.ref.store %a to %a_ref : i1, !simulation.ref<i1>
      %b_ref = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      simulation.ref.store %b to %b_ref : i1, !simulation.ref<i1>
      simulation.return
    }
  }
}

// CHECK-LABEL: llvm.func @truth(
// CHECK-SAME: %{{.*}}: !llvm.ptr, %{{.*}}: i1, %{{.*}}: i8, %[[UNKNOWN:[a-z0-9]+]]: i8)
// CHECK-NOT: %[[UNKNOWN]]{{[^0-9]}}
// CHECK: ^bb1(%{{[0-9]+}}: i8, %[[JOINED:[0-9]+]]: i8):
// CHECK-NOT: %[[JOINED]]{{[^0-9]}}
// CHECK: llvm.return

// Without the proof both unknown planes feed the X/Z tests.
// NO-PROOF-LABEL: llvm.func @truth(
// NO-PROOF-SAME: %{{.*}}: i8, %[[UNKNOWN:[a-z0-9]+]]: i8)
// NO-PROOF: llvm.xor %[[UNKNOWN]],
// NO-PROOF: ^bb1(%{{[0-9]+}}: i8, %[[JOINED:[0-9]+]]: i8):
// NO-PROOF: llvm.xor %[[JOINED]],
