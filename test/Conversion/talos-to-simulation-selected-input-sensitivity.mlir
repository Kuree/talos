// RUN: talos-opt %s --pass-pipeline='builtin.module(talos-sim-prepare-unit-lowering,simulation.design(simulation.func(talos-sim-lower-unit)))' | FileCheck %s

// IEEE 1800-2023 9.2.2.2.1, 9.2.2.3 and 11.5.3: reading a constant select
// watches only its longest static prefix, even when the process never writes
// the source declaration. A dynamic select still watches the whole prefix.

!logic = !talos.integral<1, false, true, 0 : 0, logic>
!vector = !talos.ranged_packed_array<7 : 0 x !logic>
!index = !talos.integral<32, true, false, 31 : 0, int>
!sim_vector = !simulation.packed_array<7 : 0 x !simulation.logic<1>>
!nibble = !talos.ranged_packed_array<3 : 0 x !logic>
!record = !talos.source_aggregate<"top", true, false, false, false, false, false, 8, 8, 8, 0, [
  {name = "high", ordinal = 0 : i32, packed_offset = 4 : i64, type = !nibble},
  {name = "low", ordinal = 1 : i32, packed_offset = 0 : i64, type = !nibble}]>
!sim_nibble = !simulation.packed_array<3 : 0 x !simulation.logic<1>>
!sim_record = !simulation.packed_struct<[
  #simulation.field<name = "high", type = !sim_nibble, ordinal = 0, packedOffset = 4>,
  #simulation.field<name = "low", type = !sim_nibble, ordinal = 1, packedOffset = 0>]>
!src_ref = !simulation.ref<!sim_vector>
!rec_ref = !simulation.ref<!sim_record>
!idx_ref = !simulation.ref<i32>

module {
  simulation.design @selected_input_sensitivity {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !sim_vector design hierarchy "top.source"
    simulation.storage.decl 1 in 0 : i32 design hierarchy "top.index"
    simulation.storage.decl 2 in 0 : !sim_record design hierarchy "top.record"
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "top.static_input"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "top.dynamic_input"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "top.whole_input"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "top.nested_input"
    simulation.code_unit.decl 5 in 0 always_latch hierarchy "top.dynamic_member"

    // source[5] watches bit 5 only.
    // CHECK-LABEL: simulation.func @static_input(
    // CHECK: %[[BIT:.*]] = simulation.ref.extract %arg1 from 5 : {{.*}} -> !simulation.ref<!simulation.logic<1>>
    // CHECK-NEXT: simulation.suspend.change %[[BIT]] to
    simulation.func @static_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %source: !src_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.source", argument = 1, kind = direct, copyOut = false>]} {
      talos.sv.statement.expression_statement attributes {node_id = 1 : i64} {
        talos.sv.expression.element_select attributes {node_id = 2 : i64, semantic_type = !logic} {
          talos.sv.expression.named_value attributes {node_id = 3 : i64, referenced_path = "top.source", referenced_symbol = @source, semantic_type = !vector} {}
          talos.sv.expression.integer_literal attributes {node_id = 4 : i64, constant_value = "5", is_signed = true, semantic_type = !index} {}
        }
      }
      simulation.return
    }

    // A nested constant select watches the final bit, not its containing
    // field: record.high[2] is physical bit 6.
    // CHECK-LABEL: simulation.func @nested_input(
    // CHECK: %[[NESTED:.*]] = simulation.ref.extract %arg1 from 6 : {{.*}} -> !simulation.ref<!simulation.logic<1>>
    // CHECK-NEXT: simulation.suspend.change %[[NESTED]] to
    simulation.func @nested_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %record: !rec_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.record", argument = 1, kind = direct, copyOut = false>]} {
      talos.sv.statement.expression_statement attributes {node_id = 15 : i64} {
        talos.sv.expression.element_select attributes {node_id = 16 : i64, semantic_type = !logic} {
          talos.sv.expression.member_access attributes {node_id = 17 : i64, field_ordinal = 0 : i64, referenced_path = "top.record.high", referenced_symbol = @high, semantic_type = !nibble} {
            talos.sv.expression.named_value attributes {node_id = 18 : i64, referenced_path = "top.record", referenced_symbol = @record, semantic_type = !record} {}
          }
          talos.sv.expression.integer_literal attributes {node_id = 19 : i64, constant_value = "2", is_signed = true, semantic_type = !index} {}
        }
      }
      simulation.return
    }

    // For record.high[index] the longest static prefix is record.high; the
    // dynamic index stays sensitive.
    // CHECK-LABEL: simulation.func @dynamic_member(
    // CHECK: %[[FIELD:.*]] = simulation.ref.extract %arg1 from 4 : {{.*}} -> !simulation.ref<!simulation.logic<4>>
    // CHECK-NEXT: simulation.suspend.any %arg2, %[[FIELD]] edges [0, 0] to
    simulation.func @dynamic_member(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %record: !rec_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %index: !idx_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 6 : i32, code_unit_id = 5 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.record", argument = 1, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.index", argument = 2, kind = direct, copyOut = false>]} {
      talos.sv.statement.expression_statement attributes {node_id = 20 : i64} {
        talos.sv.expression.element_select attributes {node_id = 21 : i64, semantic_type = !logic} {
          talos.sv.expression.member_access attributes {node_id = 22 : i64, field_ordinal = 0 : i64, referenced_path = "top.record.high", referenced_symbol = @high, semantic_type = !nibble} {
            talos.sv.expression.named_value attributes {node_id = 23 : i64, referenced_path = "top.record", referenced_symbol = @record, semantic_type = !record} {}
          }
          talos.sv.expression.named_value attributes {node_id = 24 : i64, referenced_path = "top.index", referenced_symbol = @index, semantic_type = !index} {}
        }
      }
      simulation.return
    }

    // source[index] watches the whole source and the index.
    // CHECK-LABEL: simulation.func @dynamic_input(
    // CHECK: simulation.suspend.any %arg1, %arg2 edges [0, 0] to
    simulation.func @dynamic_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %source: !src_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %index: !idx_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.source", argument = 1, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.index", argument = 2, kind = direct, copyOut = false>]} {
      talos.sv.statement.expression_statement attributes {node_id = 5 : i64} {
        talos.sv.expression.element_select attributes {node_id = 6 : i64, semantic_type = !logic} {
          talos.sv.expression.named_value attributes {node_id = 7 : i64, referenced_path = "top.source", referenced_symbol = @source, semantic_type = !vector} {}
          talos.sv.expression.named_value attributes {node_id = 8 : i64, referenced_path = "top.index", referenced_symbol = @index, semantic_type = !index} {}
        }
      }
      simulation.return
    }

    // Reading the whole source as well as a selected bit retains one whole
    // source watch rather than narrowing it to the bit.
    // CHECK-LABEL: simulation.func @whole_input(
    // CHECK: simulation.suspend.change %arg1 to
    simulation.func @whole_input(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %source: !src_ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.source", argument = 1, kind = direct, copyOut = false>]} {
      talos.sv.statement.expression_statement attributes {node_id = 9 : i64} {
        talos.sv.expression.element_select attributes {node_id = 10 : i64, semantic_type = !logic} {
          talos.sv.expression.named_value attributes {node_id = 11 : i64, referenced_path = "top.source", referenced_symbol = @source, semantic_type = !vector} {}
          talos.sv.expression.integer_literal attributes {node_id = 12 : i64, constant_value = "5", is_signed = true, semantic_type = !index} {}
        }
      }
      talos.sv.statement.expression_statement attributes {node_id = 13 : i64} {
        talos.sv.expression.named_value attributes {node_id = 14 : i64, referenced_path = "top.source", referenced_symbol = @source, semantic_type = !vector} {}
      }
      simulation.return
    }
  }
}
