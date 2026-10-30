// RUN: talos-opt %s | talos-opt | FileCheck %s
// IEEE 1801-2018 5.4/6.22: retain references, widths, signedness, fill and OFF.
#a = #upf.token<opcode = control, control = "top.a", isSigned = true>
#b = #upf.token<opcode = control, control = "top.b">
#ones = #upf.token<opcode = constant, value = -1 : i8, unknown = 0 : i8, isSigned = true>
#fill = #upf.token<opcode = constant, value = true, unknown = false, fill = true>
#on = #upf.expression<[#a, #ones, #upf.token<opcode = eq>, #b, #upf.token<opcode = not>, #upf.token<opcode = and>]>
#off = #upf.expression<[#b, #fill, #upf.token<opcode = ne>]>
module {
  // CHECK: upf.domain @PD elements ["top.dut"] on [
  // CHECK-SAME: control = "top.a", isSigned = true
  // CHECK-SAME: value = -1 : i8, unknown = 0 : i8, isSigned = true
  // CHECK-SAME: #upf.token<opcode = eq>
  // CHECK-SAME: #upf.token<opcode = and>
  // CHECK-SAME: off = #upf.state<name = "OFF", condition = <
  // CHECK-SAME: fill = true
  upf.domain @PD elements ["top.dut"] on [#upf.state<name = "ON", condition = #on>] {off = #upf.state<name = "OFF", condition = #off>}
}
