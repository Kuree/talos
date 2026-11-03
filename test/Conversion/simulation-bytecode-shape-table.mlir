// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --test-talos-print-bytecode='metadata=true shapes=true' -o /dev/null \
// RUN:   2>&1 | FileCheck %s

// Two-tier B4: a register's layout record is its shape index and frame
// offset; registers of equal kind, flags, width, size and auxiliary word share
// one shape, across functions too. Each register keeps its own offset.
// CHECK: shapes 2 registers 7
// CHECK-NEXT: shape 0: kind=3 flags=0 width=256 size=32 auxiliary=0
// CHECK-NEXT: shape 1: kind=2 flags=0 width=8 size=16 auxiliary=0
// CHECK-NOT: shape 2:
// CHECK: function 0: id=1
// CHECK-NEXT: layout function=0 register=0 kind=3 flags=0 width=256 offset=0 size=32
// CHECK-NEXT: layout function=0 register=1 kind=3 flags=0 width=256 offset=32 size=32
// CHECK-NEXT: layout function=0 register=2 kind=2 flags=0 width=8 offset=64 size=16
// CHECK-NEXT: function 1: id=2
// CHECK-NEXT: layout function=1 register=0 kind=3 flags=0 width=256 offset=0 size=32
// CHECK-NEXT: layout function=1 register=1 kind=3 flags=0 width=256 offset=32 size=32
// CHECK-NEXT: layout function=1 register=2 kind=2 flags=0 width=8 offset=64 size=16
// CHECK-NEXT: layout function=1 register=3 kind=2 flags=0 width=8 offset=80 size=16

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @shapes {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 initial hierarchy "shapes.first"
    simulation.code_unit.decl 2 in 0 initial hierarchy "shapes.second"
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design

    simulation.func @first(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }

    simulation.func @second(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<8>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %other = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %other to %state :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
  }
}
