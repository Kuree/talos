// RUN: talos-opt %s | talos-opt | FileCheck %s
module {
  // CHECK: upf.domain @PD elements ["top.dut"] control "top.power_en" on_high = true
  upf.domain @PD elements ["top.dut"] control "top.power_en" on_high = true {
    isolation_control = "top.iso", isolation_high = false, clamp = 1 : i64
  }
}
