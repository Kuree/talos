// RUN: talos-opt %s --pass-pipeline='builtin.module(talos-sim-prepare-unit-lowering,simulation.design(simulation.func(talos-sim-lower-unit)))' | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(talos-sim-prepare-unit-lowering,simulation.design(simulation.func(talos-sim-lower-unit),talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.mlir
// RUN: FileCheck %s --check-prefix=GRAPH < %t.mlir
// RUN: talos-opt %t.mlir '--encode-talos-sim-to-bytecode=vpi=off' --test-talos-print-bytecode -o /dev/null 2>&1 | FileCheck %s --check-prefix=BYTECODE
// RUN: talos-opt %t.mlir --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=NATIVE

// IEEE 1800-2023 9.2.2/9.4.2: the leading event control is encountered again
// after the controlled body completes. It is not armed while that body runs.
// Keep the leading-wait identity, but do not add a self-wakeup edge from the
// body's blocking assignment to the next iteration's wait.
// GRAPH: edges = [#schedule.edge<source = 0, target = 1, kind = process_order>, #schedule.edge<source = 1, target = 2, kind = resume>, #schedule.edge<source = 2, target = 1, kind = process_order>]
// The serialized wait header has version 1, kind 3, flags 4
// (SUPPRESS_ACTIVE_SELF), and two watched expressions.
// BYTECODE: constants: 01000000030000000400000002000000
// NATIVE-LABEL: llvm.mlir.global internal constant @event_loop.__talos_table.waits()
// NATIVE: %[[FLAGS:[0-9]+]] = llvm.mlir.constant(4 : i32)
// NATIVE-NEXT: %{{[0-9]+}} = llvm.insertvalue %[[FLAGS]], %{{[0-9]+}}[2]

!logic1 = !talos.integral<1, false, true, 0 : 0, logic>

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @explicit_event_self_trigger {
    simulation.code_unit.decl 9903001 in 0 always hierarchy "top.event_loop"
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
        hierarchy "top.a"
    simulation.storage.decl 1 in 0 : !simulation.logic<1> design
        hierarchy "top.c"

    // CHECK-LABEL: simulation.func @event_loop
    // CHECK: simulation.suspend.any
    // CHECK-SAME: {schedule.procedural_event_wait, schedule.repeating_always_wait}
    simulation.func @event_loop(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %a: !simulation.ref<!simulation.logic<1>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 0 : i64},
        %c: !simulation.ref<!simulation.logic<1>>
            {simulation.capture_kind = 3 : i32,
             simulation.descriptor_id = 1 : i64})
        attributes {
          entry_kind = 3 : i32,
          simulation.bindings = [
            #simulation.argument_binding<path = "top.a", argument = 1,
                kind = direct, copyOut = false>,
            #simulation.argument_binding<path = "top.c", argument = 2,
                kind = direct, copyOut = false>
          ],
          simulation.delay_quantum = 1 : i64,
          simulation.delay_scale = 1 : i64,
          code_unit_id = 9903001 : i64
        } {
      talos.sv.statement.timed attributes {node_id = 1 : i64} {
        talos.sv.timing.event_list attributes {
            event_count = 2 : i64, node_id = 2 : i64} {
          talos.sv.timing.signal_event attributes {
              edge_kind = 0 : i32, has_iff = false, node_id = 3 : i64} {
            talos.sv.expression.named_value attributes {
                is_signed = false, node_id = 4 : i64,
                referenced_path = "top.a", referenced_symbol = @a,
                semantic_type = !logic1} {
            }
          }
          talos.sv.timing.signal_event attributes {
              edge_kind = 0 : i32, has_iff = false, node_id = 5 : i64} {
            talos.sv.expression.named_value attributes {
                is_signed = false, node_id = 6 : i64,
                referenced_path = "top.c", referenced_symbol = @c,
                semantic_type = !logic1} {
            }
          }
        }
        talos.sv.statement.expression_statement attributes {node_id = 7 : i64} {
          talos.sv.expression.assignment attributes {
              assignment_kind = 0 : i32, is_signed = false,
              node_id = 8 : i64, semantic_type = !logic1} {
            talos.sv.expression.named_value attributes {
                is_signed = false, node_id = 9 : i64,
                referenced_path = "top.a", referenced_symbol = @a,
                semantic_type = !logic1} {
            }
            talos.sv.expression.integer_literal attributes {
                constant_value = "1'b0", is_signed = false,
                node_id = 10 : i64, semantic_type = !logic1} {
            }
          }
        }
      }
      simulation.return
    }
  }
}
