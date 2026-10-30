// RUN: talos-opt %s | talos-opt | FileCheck %s
// IEEE 1801-2018 6.22: preserve state names, kinds and independent conditions.
#a = #upf.expression<[#upf.token<opcode = control, control = "top.a">]>
#b = #upf.expression<[#upf.token<opcode = control, control = "top.b">]>
#fault = #upf.expression<[#upf.token<opcode = control, control = "top.fault">]>
#off = #upf.expression<[#upf.token<opcode = control, control = "top.off">]>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  upf.supply @never_supply names ["/top/NEVER"] writable = false
  // CHECK: upf.domain @PD elements ["top.dut"] power @switched on [#upf.state<name = "FIRST"
  // CHECK-SAME: control = "top.a"
  // CHECK-SAME: #upf.state<name = "SECOND"
  // CHECK-SAME: control = "top.b"
  // CHECK-SAME: errors = [#upf.state<name = "FAULT"
  // CHECK-SAME: control = "top.fault"
  // CHECK-SAME: off = #upf.state<name = "OFF"
  upf.domain @PD elements ["top.dut"] power @switched on [
    #upf.state<name = "FIRST", condition = #a>,
    #upf.state<name = "SECOND", condition = #b>
  ] {input = @rail,
    errors = [#upf.state<name = "FAULT", condition = #fault>],
    off = #upf.state<name = "OFF", condition = #off>
  }
  // CHECK: upf.domain @never elements ["top.never"] power @never_supply on []
  upf.domain @never elements ["top.never"] power @never_supply on [] {input = @rail}
}
