// RUN: talos-opt %s | talos-opt | FileCheck %s
#on = #upf.expression<[#upf.token<opcode = control, control = "top.power_en">]>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // CHECK: upf.domain @PD elements ["top.dut"] power @switched on
  upf.domain @PD elements ["top.dut"] power @switched on [#upf.state<name = "ON", condition = #on>] {input = @rail,
    isolation_control = "top.iso", isolation_high = false, clamp = 1 : i64
  }
}
