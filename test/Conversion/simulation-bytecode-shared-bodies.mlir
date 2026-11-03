// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --test-talos-print-bytecode='metadata=true shapes=true' -o /dev/null \
// RUN:   2>&1 \
// RUN:   | FileCheck %s

// Two-tier B4: functions with equal bodies share one instruction range and one
// layout range. Constants, operand runs and sites are interned, and a
// continuation is named by its ordinal among the function's records, so
// @first and @second (different code units, state and continuation ids 5 and
// 9) encode equal bodies whose SUSPEND names ordinal 1; @third differs in its
// delay constant. Each function keeps its own continuation records (ids are
// the cross-tier ABI), pointing into the shared range; the kept ranges are
// compacted and their jump targets rebased.
// Six registers per function; @first and @second share one layout range.
// CHECK: shapes 4 registers 12
// CHECK: function 0: id=1 rank=0 first_instruction=0 instruction_count=15
// CHECK: function 1: id=2 rank=1 first_instruction=0 instruction_count=15
// CHECK: function 2: id=3 rank=2 first_instruction=15 instruction_count=15
// CHECK: 6: opcode=34 flags=1 {{.*}} imm=1
// CHECK: 14: opcode=29 {{.*}} imm=7
// CHECK: 16: opcode=1 flags=0 dst=3 {{.*}} imm=80
// CHECK: 21: opcode=34 flags=1 {{.*}} imm=1
// CHECK: 26: opcode=29 {{.*}} imm=15
// CHECK: 29: opcode=29 {{.*}} imm=22
// CHECK-NOT: {{^}}30: opcode
// CHECK: continuation 0: function=0 id=0 instruction=9 rank=0
// CHECK-NEXT: continuation 1: function=0 id=5 instruction=12 rank=0
// CHECK-NEXT: continuation 2: function=1 id=0 instruction=9 rank=1
// CHECK-NEXT: continuation 3: function=1 id=9 instruction=12 rank=1
// CHECK-NEXT: continuation 4: function=2 id=0 instruction=24 rank=2
// CHECK-NEXT: continuation 5: function=2 id=7 instruction=27 rank=2

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @shared {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 initial hierarchy "shared.first"
    simulation.code_unit.decl 2 in 0 initial hierarchy "shared.second"
    simulation.code_unit.decl 3 in 0 initial hierarchy "shared.third"
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design
    simulation.storage.decl 1 in 0 : !simulation.logic<8> design

    simulation.func @first(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^resume
          {site = #schedule.continuation<id = 5>}
    ^resume:
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }

    simulation.func @second(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 1 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^resume
          {site = #schedule.continuation<id = 9>}
    ^resume:
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }

    simulation.func @third(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^resume
          {site = #schedule.continuation<id = 7>}
    ^resume:
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
  }
}
