// RUN: talos-opt %s '--lower-talos-to-sim=opt-level=0' | FileCheck %s

// IEEE 1800-2023 21.2.3: a $monitor whose argument is a plain variable waits
// on an observer of it like any other argument, so a generated periodic loop
// can compare it at the end of each time slot (4.4.2.9) instead of the runtime
// subscribing to the variable.
module {
  talos.sv.symbol.definition @s0.top attributes {definition_kind = 0 : i32, hierarchical_name = "top", name = "top", node_id = 0 : i64} {
  }
  talos.sv.symbol.root @s1.$root attributes {hierarchical_name = "\\$root ", name = "$root", node_id = 1 : i64} {
    talos.sv.symbol.compilation_unit @s2 attributes {hierarchical_name = "$unit", node_id = 2 : i64} {
    }
    talos.sv.symbol.instance @s3.top attributes {hierarchical_name = "top", is_uninstantiated = false, name = "top", node_id = 3 : i64, referenced_path = "top", referenced_symbol = @s0.top} {
      talos.sv.symbol.instance_body @s4.top attributes {hierarchical_name = "top", name = "top", node_id = 4 : i64} {
        talos.sv.symbol.variable @s5.value attributes {hierarchical_name = "top.value", lifetime = 1 : i32, name = "value", node_id = 5 : i64, semantic_type = !talos.integral<1, false, true, 0 : 0, reg>} {
        }
        talos.sv.symbol.procedural_block @s6 attributes {hierarchical_name = "top", node_id = 6 : i64, procedure_kind = 0 : i32, time_precision_fs = 1000000 : i64, time_unit_fs = 1000000 : i64} {
          talos.sv.statement.expression_statement attributes {node_id = 7 : i64} {
            talos.sv.expression.call attributes {argument_count = 1 : i64, callee_name = "$monitor", constraint_restrictions = [], has_inline_constraints = false, has_iterator_expression = false, has_output_arguments = false, has_this_class = false, is_super_class = false, is_system_call = true, node_id = 8 : i64, semantic_type = !talos.void, subroutine_kind = 1 : i32, system_library_cell = "work.top", system_scope_path = "top", system_scope_symbol = @s1.$root::@s3.top::@s4.top} {
              talos.sv.expression.named_value attributes {is_signed = false, node_id = 9 : i64, referenced_path = "top.value", referenced_symbol = @s1.$root::@s3.top::@s4.top::@s5.value, semantic_type = !talos.integral<1, false, true, 0 : 0, reg>} {
              }
            }
          }
        }
      }
    }
  }
}

// CHECK: simulation.func private @[[CALLBACK:unit_0[.][^(]+]](
// CHECK-SAME: simulation.persistent_monitor
// CHECK: simulation.observer.bind
// CHECK: simulation.display
// CHECK-NOT: simulation.suspend.change
// CHECK: simulation.suspend.observe
// CHECK-SAME: resume_region = 16
// CHECK-LABEL: simulation.func private @unit_0(
// CHECK: %[[PROCESS:.*]] = simulation.spawn @[[CALLBACK]]
// CHECK: simulation.monitor.register %[[PROCESS]]
