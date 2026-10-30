// RUN: talos-opt %s | talos-opt | FileCheck %s
#on = #upf.expression<[#upf.token<opcode = control, control = "top.power_en">]>
module {
  // CHECK: upf.domain @PD elements ["top.dut"] on
  upf.domain @PD elements ["top.dut"] on [#upf.state<name = "ON", condition = #on>] {
    isolation_control = "top.iso", isolation_high = false, clamp = 1 : i64
  }
}
