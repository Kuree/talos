// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' | FileCheck %s
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --test-talos-print-bytecode='metadata=true' -o /dev/null 2>&1 \
// RUN:   | FileCheck %s --check-prefix=PRINT
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off' \
// RUN:   --convert-talos-sim-processes-to-llvm-coroutines -o /dev/null

!bundle = !simulation.unpacked_struct<[
  #simulation.field<name = "object", type = !simulation.class_handle<@Base>,
                     ordinal = 0, packedOffset = 0>
]>

module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @virtual_tasks {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 initial hierarchy "top.caller"
    simulation.code_unit.decl 2 in 0 task hierarchy "Base.run"
    simulation.code_unit.decl 3 in 0 initial hierarchy "top.class_caller"

    simulation.class.decl @Runner id 1 {
      is_abstract = true, is_final = false, is_interface = true
    }
    simulation.class.decl @Base id 2 implements [@Runner] {
      is_abstract = false, is_final = true, is_interface = false
    }
    simulation.class.method @Runner_run of @Runner slot 4294967295
      signature_id 17 interface_ordinal 0 :
      (!simulation.context, !simulation.class_handle<@Runner>, i32,
       !bundle) -> () {
        is_final = false, is_pure = true, is_static = false,
        is_task = true, is_virtual = true
      }
    simulation.class.method @Base_run of @Base slot 0 signature_id 17
      implemented_by @base_run :
      (!simulation.context, !simulation.class_handle<@Base>, i32,
       !bundle) -> () {
        is_final = false, is_pure = false, is_static = false,
        is_task = true, is_virtual = true
      }

    simulation.func @base_run(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %this: !simulation.class_handle<@Base>
          {simulation.capture_kind = 1 : i32},
        %value: i32 {simulation.capture_kind = 2 : i32},
        %bundle: !bundle {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 12 : i32} {
      // Retain activation dispatch: timing excludes the synchronous native ABI.
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^done
    ^done:
      simulation.return
    }

    simulation.func @caller(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 1 : i32} {
      %receiver = simulation.class.alloc %ctx :
        !simulation.context -> !simulation.class_handle<@Base>
      %interface = simulation.class.cast %receiver :
        !simulation.class_handle<@Base> to
        !simulation.class_handle<@Runner>
      %value = arith.constant 42 : i32
      %empty = simulation.aggregate.default : !bundle
      %bundle = simulation.aggregate.insert %receiver into %empty[0] :
        (!bundle, !simulation.class_handle<@Base>) -> !bundle
      simulation.class.virtual_task_call
        %interface[@Runner_run] slot 4294967295 signature_id 17
        (%value, %bundle, %bundle) arguments 2 to ^done :
        (!simulation.class_handle<@Runner>, i32, !bundle, !bundle) -> ()
    ^done(%continued: !bundle):
      simulation.return
    }

    simulation.func @class_caller(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 1 : i32} {
      %receiver = simulation.class.alloc %ctx :
        !simulation.context -> !simulation.class_handle<@Base>
      %value = arith.constant 9 : i32
      %empty = simulation.aggregate.default : !bundle
      %bundle = simulation.aggregate.insert %receiver into %empty[0] :
        (!bundle, !simulation.class_handle<@Base>) -> !bundle
      simulation.class.virtual_task_call
        %receiver[@Base_run] slot 0 signature_id 17
        (%value, %bundle) arguments 2 to ^done :
        (!simulation.class_handle<@Base>, i32, !bundle) -> ()
    ^done:
      simulation.return
    }
  }
}

// Opcode 57 carries interface-dispatch record 8, receiver register 2,
// argument-map offset 9/count 4, continuation ordinal 1, and signature ID
// 17. The dispatch record stores interface ID 1 and ordinal 0.
// The managed continuation is stored before dispatch, restored on resume, and
// then removed from the canonical frame's precise root inventory.
// CHECK: runtime.bytecode_image = array<i8:
// PRINT: operand 8: dst=1 src=0
// PRINT: opcode=24 flags=0 dst=0 src0=5 src1=0 src2=0 aux=8 imm=0
// PRINT-NEXT: opcode=57 flags=0 dst=8 src0=2 src1=9 src2=4 aux=1 imm=17
// PRINT: opcode=23 flags=0 dst=6 src0=0 src1=0 src2=0 aux=8 imm=0
// PRINT-NEXT: opcode=42 flags=0 dst=0 src0=0 src1=0 src2=0 aux=0 imm=0
// PRINT: opcode=55 flags=0 dst=0 src0=0 src1=0 src2=0 aux=0 imm=16
// PRINT: opcode=54 flags=0 dst=0
// CHECK: runtime.bytecode_function = 1 : i32
// CHECK: runtime.bytecode_function = 0 : i32
