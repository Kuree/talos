// RUN: talos-opt %s --test-talos-source-memory-forwarding | FileCheck %s
!tagged = !simulation.packed_union<fields = [#simulation.field<name = "a", type = i8, ordinal = 0, packedOffset = 0>, #simulation.field<name = "b", type = i8, ordinal = 1, packedOffset = 0>], isTagged = true, tagBits = 1>
module {
  simulation.design @forwarding {
    simulation.scope.decl 0
    simulation.storage.decl 3 in 0 : !tagged design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 0 in 0 : !simulation.logic<16> design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : !simulation.logic<8> design
    simulation.storage.decl 5 in 0 : i32 design
    simulation.storage.decl 6 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 function hierarchy "forwarded_offset"
    // An offset load is itself forwarded before the dependent slice load.
    // Frozen analysis facts must follow that replacement, including X/Z bits.
    // CHECK-LABEL: simulation.func @forwarded_offset
    // CHECK: %[[BITS:.*]] = simulation.logic.constant
    // CHECK: %[[OFFSET:.*]] = arith.constant 4 : i32
    // CHECK-NOT: simulation.ref.load
    // CHECK: %[[RESULT:.*]] = simulation.logic.dyn_extract %[[BITS]] from %[[OFFSET]]
    // CHECK: simulation.ref.store %[[RESULT]]
    simulation.func @forwarded_offset(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %packed = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<16>>
      %index = simulation.context.storage %ctx[1] : !simulation.ref<i32>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<8>>
      %bits = simulation.logic.constant 1234 : i16, 80 : i16 : !simulation.logic<16>
      %four = arith.constant 4 : i32
      simulation.ref.store %bits to %packed : !simulation.logic<16>, !simulation.ref<!simulation.logic<16>>
      simulation.ref.store %four to %index : i32, !simulation.ref<i32>
      %offset = simulation.ref.load %index : !simulation.ref<i32> -> i32
      %slice = simulation.ref.dyn_extract %packed from %offset : (!simulation.ref<!simulation.logic<16>>, i32) -> !simulation.ref<!simulation.logic<8>>
      %value = simulation.ref.load %slice : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %output : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
    simulation.code_unit.decl 2 in 0 function hierarchy "alias_kill"
    // A possibly overlapping slice store invalidates the aggregate snapshot.
    // CHECK-LABEL: simulation.func @alias_kill
    // CHECK: %[[READ:.*]] = simulation.ref.load
    // CHECK: simulation.ref.store %[[READ]]
    simulation.func @alias_kill(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %packed = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<16>>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<8>>
      %bits = simulation.logic.constant 1234 : i16, 80 : i16 : !simulation.logic<16>
      %zero = simulation.logic.constant 0 : i8, 0 : i8 : !simulation.logic<8>
      simulation.ref.store %bits to %packed : !simulation.logic<16>, !simulation.ref<!simulation.logic<16>>
      %alias = simulation.ref.extract %packed from 4 : !simulation.ref<!simulation.logic<16>> -> !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %zero to %alias : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      %slice = simulation.ref.extract %packed from 0 : !simulation.ref<!simulation.logic<16>> -> !simulation.ref<!simulation.logic<8>>
      %value = simulation.ref.load %slice : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %output : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
    simulation.code_unit.decl 3 in 0 initial hierarchy "suspension_kill"
    // External writes between activations must be observed after the wait.
    // CHECK-LABEL: simulation.func @suspension_kill
    // CHECK: simulation.suspend.delay
    // CHECK: %[[READ:.*]] = simulation.ref.load
    // CHECK: simulation.ref.store %[[READ]]
    simulation.func @suspension_kill(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %packed = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<16>>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<8>>
      %bits = simulation.logic.constant 1234 : i16, 80 : i16 : !simulation.logic<16>
      simulation.ref.store %bits to %packed : !simulation.logic<16>, !simulation.ref<!simulation.logic<16>>
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^resume
    ^resume:
      %slice = simulation.ref.extract %packed from 0 : !simulation.ref<!simulation.logic<16>> -> !simulation.ref<!simulation.logic<8>>
      %value = simulation.ref.load %slice : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %output : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
    // IEEE 1800-2023 7.3.2: a field load retains tagged-member validation.
    // CHECK-LABEL: simulation.func @tagged_member
    // CHECK: simulation.ref.store
    // CHECK: %[[TAGGED:.*]] = simulation.ref.subelement
    // CHECK: %[[READ:.*]] = simulation.ref.load %[[TAGGED]]
    // CHECK: simulation.ref.store %[[READ]]
    simulation.code_unit.decl 4 in 0 function hierarchy "tagged_member"
    simulation.func @tagged_member(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %parent = simulation.context.storage %ctx[3] : !simulation.ref<!tagged>
      %out = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      %one = arith.constant 1 : i8
      %value = simulation.union.construct %one as 0 : (i8) -> !tagged
      simulation.ref.store %value to %parent : !tagged, !simulation.ref<!tagged>
      %member = simulation.ref.subelement %parent[[1]] : !simulation.ref<!tagged> -> !simulation.ref<i8>
      %read = simulation.ref.load %member : !simulation.ref<i8> -> i8
      simulation.ref.store %read to %out : i8, !simulation.ref<i8>
      simulation.return
    }
    // Distinct predecessor values are not a must-value at the CFG merge.
    // CHECK-LABEL: simulation.func @different_join
    // CHECK: cf.cond_br
    // CHECK: %[[READ:.*]] = simulation.ref.load
    // CHECK: simulation.ref.store %[[READ]]
    simulation.code_unit.decl 5 in 0 function hierarchy "different_join"
    simulation.func @different_join(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %packed = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<16>>
      %index = simulation.context.storage %ctx[1] : !simulation.ref<i32>
      %out = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<8>>
      %a = simulation.logic.constant 1 : i16, 0 : i16 : !simulation.logic<16>
      %b = simulation.logic.constant 2 : i16, 0 : i16 : !simulation.logic<16>
      %i = simulation.ref.load %index : !simulation.ref<i32> -> i32
      %zero = arith.constant 0 : i32
      %cond = arith.cmpi eq, %i, %zero : i32
      cf.cond_br %cond, ^left, ^right
    ^left:
      simulation.ref.store %a to %packed : !simulation.logic<16>, !simulation.ref<!simulation.logic<16>>
      cf.br ^join
    ^right:
      simulation.ref.store %b to %packed : !simulation.logic<16>, !simulation.ref<!simulation.logic<16>>
      cf.br ^join
    ^join:
      %slice = simulation.ref.extract %packed from 0 : !simulation.ref<!simulation.logic<16>> -> !simulation.ref<!simulation.logic<8>>
      %read = simulation.ref.load %slice : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %read to %out : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
    // A join whose other predecessor has a side effect knows nothing, so its
    // load is kept; a re-read below that load still uses it. The solver first
    // visits the join with the fallthrough predecessor's older read, and the
    // load must not publish that older name, or the settled visit would
    // conflict with it and drop the fact for the re-read.
    // CHECK-LABEL: simulation.func @reread_after_join
    // CHECK: simulation.time.now
    // CHECK: ^[[JOIN:bb[0-9]+]]:
    // CHECK-NEXT: %[[SECOND:.*]] = simulation.ref.load
    // CHECK-NOT: simulation.ref.load
    // CHECK: %[[NARROW:.*]] = arith.trunci %[[SECOND]]
    // CHECK-NEXT: simulation.ref.store %[[NARROW]]
    // CHECK: simulation.return
    simulation.code_unit.decl 6 in 0 function hierarchy "reread_after_join"
    simulation.func @reread_after_join(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %flag = simulation.context.storage %ctx[1] : !simulation.ref<i32>
      %copy = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      %zero = arith.constant 0 : i32
      %first = simulation.ref.load %flag : !simulation.ref<i32> -> i32
      %low = arith.cmpi eq, %first, %zero : i32
      cf.cond_br %low, ^join, ^side
    ^side:
      %now = simulation.time.now %ctx
      cf.br ^join
    ^join:
      %second = simulation.ref.load %flag : !simulation.ref<i32> -> i32
      %again = arith.cmpi eq, %second, %zero : i32
      cf.cond_br %again, ^reread, ^done
    ^reread:
      %third = simulation.ref.load %flag : !simulation.ref<i32> -> i32
      %narrow = arith.trunci %third : i32 to i8
      simulation.ref.store %narrow to %copy : i8, !simulation.ref<i8>
      cf.br ^done
    ^done:
      simulation.return
    }
    // A store before a loop names the contents on entry; the loop's own load
    // adds a name the back edge carries, and the header keeps the shared one.
    // CHECK-LABEL: simulation.func @loop_invariant
    // CHECK: %[[V:.*]] = simulation.ref.load
    // CHECK-NOT: simulation.ref.load
    // CHECK: arith.addi %[[V]],
    simulation.code_unit.decl 7 in 0 function hierarchy "loop_invariant"
    simulation.func @loop_invariant(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %flag = simulation.context.storage %ctx[5] : !simulation.ref<i32>
      %src = simulation.context.storage %ctx[6] : !simulation.ref<i32>
      %out = simulation.context.storage %ctx[1] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      %ten = arith.constant 10 : i32
      %v = simulation.ref.load %src : !simulation.ref<i32> -> i32
      simulation.ref.store %v to %flag : i32, !simulation.ref<i32>
      cf.br ^head(%zero : i32)
    ^head(%i: i32):
      %x = simulation.ref.load %flag : !simulation.ref<i32> -> i32
      %s = arith.addi %x, %i : i32
      simulation.ref.store %s to %out : i32, !simulation.ref<i32>
      %n = arith.addi %i, %one : i32
      %c = arith.cmpi slt, %n, %ten : i32
      cf.cond_br %c, ^head(%n : i32), ^exit
    ^exit:
      simulation.return
    }
    // A load in one arm adds a name only that arm knows; the join keeps the
    // stored value both arms share, and both later loads use it.
    // CHECK-LABEL: simulation.func @store_branch_load_join
    // CHECK: %[[V:.*]] = simulation.ref.load
    // CHECK-NOT: simulation.ref.load
    // CHECK: arith.trunci %[[V]]
    simulation.code_unit.decl 8 in 0 function hierarchy "store_branch_load_join"
    simulation.func @store_branch_load_join(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 8 : i64} {
      %flag = simulation.context.storage %ctx[5] : !simulation.ref<i32>
      %copy = simulation.context.storage %ctx[4] : !simulation.ref<i8>
      %other = simulation.context.storage %ctx[1] : !simulation.ref<i32>
      %src = simulation.context.storage %ctx[6] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %v = simulation.ref.load %src : !simulation.ref<i32> -> i32
      %c = arith.cmpi eq, %v, %zero : i32
      simulation.ref.store %v to %flag : i32, !simulation.ref<i32>
      cf.cond_br %c, ^a, ^join
    ^a:
      %x = simulation.ref.load %flag : !simulation.ref<i32> -> i32
      simulation.ref.store %x to %other : i32, !simulation.ref<i32>
      cf.br ^join
    ^join:
      %y = simulation.ref.load %flag : !simulation.ref<i32> -> i32
      %narrow = arith.trunci %y : i32 to i8
      simulation.ref.store %narrow to %copy : i8, !simulation.ref<i8>
      simulation.return
    }
  }
}
