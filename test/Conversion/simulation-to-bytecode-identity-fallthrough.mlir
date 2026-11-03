// RUN: talos-opt %s --split-input-file --encode-talos-sim-to-bytecode='vpi=off' '--test-talos-print-bytecode=metadata=true' -o /dev/null 2>&1 | FileCheck %s

// A representation change between equal register layouts shares its operand's
// register and encodes no instruction; one that changes the layout (a known
// i32 widened to a four-state register) still converts. A jump without block
// arguments to the block encoded next falls through; back edges and jumps
// that carry block arguments stay.
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @identity_fallthrough {
    simulation.code_unit.decl 9200001 in 0 function hierarchy "test.identity.9200001"
    simulation.scope.decl 0 hierarchy "top"

    simulation.func @convert(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %packed: !simulation.packed_array<3 : 0 x !simulation.logic<8>>
            {simulation.capture_kind = 1 : i32},
        %bits: i32 {simulation.capture_kind = 1 : i32},
        %again: i1 {simulation.capture_kind = 1 : i32})
        -> !simulation.logic<32>
        attributes {entry_kind = 8 : i32, code_unit_id = 9200001 : i64} {
      %flat = simulation.packed.flatten %packed :
          (!simulation.packed_array<3 : 0 x !simulation.logic<8>>)
          -> !simulation.logic<32>
      %wide = simulation.logic.from_bits %bits : i32 -> !simulation.logic<32>
      cf.br ^body
    ^body:
      %sum = simulation.logic.binary add %flat, %wide : !simulation.logic<32>
      cf.cond_br %again, ^done(%sum : !simulation.logic<32>), ^retry
    ^retry:
      cf.br ^body
    ^done(%result: !simulation.logic<32>):
      simulation.return %result : !simulation.logic<32>
    }
  }
}

// Registers 0-3 are the arguments (1 is %packed). The flatten encodes nothing
// and the add reads register 1; from_bits stays an EXTRACT (opcode 21). The
// entry's jump to ^body and the false edge to ^retry fall through; BRANCH
// (30) carries ^done's argument and ^retry's back edge stays a JUMP (29).
// CHECK: 0: opcode=21 flags=0 dst=[[WIDE:[0-9]+]] src0=2 src1=4294967295
// CHECK-NEXT: 1: opcode=7 flags=0 dst={{[0-9]+}} src0=1 src1=[[WIDE]]
// CHECK-NEXT: 2: opcode=30 flags=0 dst=3 src0={{[0-9]+}} src1=1 {{.*}} imm=4{{$}}
// CHECK-NEXT: 3: opcode=29 flags=0 {{.*}} src1=0 {{.*}} imm=1{{$}}
// CHECK-NEXT: 4: opcode=32

// -----

// A shared register whose operand is a loop-header argument: the back edge's
// parallel copy redefines %x, and %rx (sharing %x's register) is only used
// where its own definition dominates. The entry's jump to ^head carries block
// arguments, so it stays a JUMP even though ^head is next; the false edge to
// ^done falls through and the return reads %x's register.
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @loop_header_alias {
    simulation.code_unit.decl 9200002 in 0 function hierarchy "test.identity.9200002"
    simulation.scope.decl 0 hierarchy "top"

    simulation.func @rotate(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %a: !simulation.logic<32> {simulation.capture_kind = 1 : i32},
        %b: !simulation.logic<32> {simulation.capture_kind = 1 : i32},
        %again: i1 {simulation.capture_kind = 1 : i32})
        -> !simulation.logic<32>
        attributes {entry_kind = 8 : i32, code_unit_id = 9200002 : i64} {
      cf.br ^head(%a, %b : !simulation.logic<32>, !simulation.logic<32>)
    ^head(%x: !simulation.logic<32>, %y: !simulation.logic<32>):
      %rx = simulation.logic.resize %x signed = false :
          !simulation.logic<32> -> !simulation.logic<32>
      %sum = simulation.logic.binary add %x, %y : !simulation.logic<32>
      cf.cond_br %again, ^head(%y, %rx : !simulation.logic<32>,
          !simulation.logic<32>), ^done
    ^done:
      simulation.return %rx : !simulation.logic<32>
    }
  }
}

// Operand maps: entry (x, y) <- (a, b); back edge (x, y) <- (y, rx) with rx
// in x's register, a swap; the return reads x's register.
// CHECK: operand 0: dst=[[X:[0-9]+]] src=1
// CHECK-NEXT: operand 1: dst=[[Y:[0-9]+]] src=2
// CHECK-NEXT: operand 2: dst=[[X]] src=[[Y]]
// CHECK-NEXT: operand 3: dst=[[Y]] src=[[X]]
// CHECK-NEXT: operand 4: dst={{[0-9]+}} src=[[X]]
// CHECK-NEXT: 0: opcode=29 flags=0 dst=0 src0=0 src1=2 {{.*}} imm=1{{$}}
// CHECK-NEXT: 1: opcode=7 flags=0 dst={{[0-9]+}} src0=[[X]] src1=[[Y]]
// CHECK-NEXT: 2: opcode=30 flags=0 dst=3 src0=2 src1=2 {{.*}} imm=1{{$}}
// CHECK-NEXT: 3: opcode=32 flags=0 dst=0 src0=4 src1=1
