// RUN: talos-opt %s | talos-opt | FileCheck %s
// IEEE 1801-2018 5.4/6.22: retain source shape and normalized static selection.
#word = #upf.token<opcode = control, control = "top.mode", isSigned = true, width = 8, sourceWidth = 8>
#part = #upf.token<opcode = control, control = "top.bus", width = 3, sourceWidth = 66, offset = 63>
#bit = #upf.token<opcode = control, control = "top.bus", sourceWidth = 66, offset = 65>
#zero = #upf.token<opcode = constant, value = 0 : i32, unknown = 0 : i32>
#pattern = #upf.token<opcode = constant, value = 5 : i3, unknown = 0 : i3>
#on = #upf.expression<[#word, #zero, #upf.token<opcode = lt>, #part, #pattern, #upf.token<opcode = eq>, #upf.token<opcode = and>]>
module {
  // CHECK: upf.domain @PD elements ["top.dut"] on
  // CHECK-SAME: width = 8, sourceWidth = 8
  // CHECK-SAME: width = 3, sourceWidth = 66, offset = 63
  // CHECK-SAME: off = #upf.state<name = "OFF", condition = <
  // CHECK-SAME: sourceWidth = 66, offset = 65
  upf.domain @PD elements ["top.dut"] on [#upf.state<name = "ON", condition = #on>] {off = #upf.state<name = "OFF", condition = #upf.expression<[#bit]>>}
}
