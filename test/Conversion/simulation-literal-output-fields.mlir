// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @literal_output {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 function hierarchy "top.render"
    simulation.func @render(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %value = simulation.logic.constant 21 : i8, 136 : i8 : !simulation.logic<8>
      %text = simulation.bytes.constant "%% %4H %-6s"
      %label = simulation.bytes.constant "name"
      %result = simulation.string.output_format %ctx(%text, %value, %label)
          radix = <decimal> flags = [32, 0, 0] : !simulation.bytes, !simulation.logic<8>, !simulation.bytes
      %time = simulation.bytes.constant "%t"
      %timed = simulation.string.output_format %ctx(%time, %value)
          radix = <decimal> flags = [32, 0] : !simulation.bytes, !simulation.logic<8>
      %extra = simulation.string.output_format %ctx(%label, %value)
          radix = <decimal> flags = [32, 0] : !simulation.bytes, !simulation.logic<8>
      %dynamic = simulation.string.output_format %ctx(%result, %value)
          radix = <decimal> flags = [40, 0] : !simulation.string, !simulation.logic<8>
      simulation.return
    }
  }
}
// CHECK-LABEL: llvm.func @render(
// CHECK: llvm.call @talos_rt_v1_string_output_fields
// CHECK-COUNT-3: llvm.call @talos_rt_v1_string_output_format
