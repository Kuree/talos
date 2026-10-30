// RUN: talos-opt --split-input-file --verify-diagnostics %s
module {
  // expected-error @+1 {{requires domain elements and a power control}}
  upf.domain @empty elements [] control "top.power" on_high = true
}
// -----
module {
  // expected-error @+1 {{domain element must not be empty}}
  upf.domain @empty_element elements [""] control "top.power" on_high = true
}
// -----
module {
  // expected-error @+1 {{isolation control must not be empty}}
  upf.domain @empty_isolation elements ["top.dut"] control "top.power" on_high = true {isolation_control = ""}
}
// -----
module {
  // expected-error @+1 {{isolation clamp must be zero or one}}
  upf.domain @clamp elements ["top.dut"] control "top.power" on_high = true {clamp = 2 : i64}
}
