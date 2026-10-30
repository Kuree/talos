// RUN: talos-opt --split-input-file --verify-diagnostics %s
module {
  // expected-error @+1 {{requires domain elements}}
  upf.domain @empty elements [] on []
}
// -----
module {
  // expected-error @+1 {{domain element must not be empty}}
  upf.domain @empty_element elements [""] on []
}
// -----
module {
  // expected-error @+1 {{isolation control must not be empty}}
  upf.domain @empty_isolation elements ["top.dut"] on [] {isolation_control = ""}
}
// -----
module {
  // expected-error @+1 {{isolation clamp must be zero or one}}
  upf.domain @clamp elements ["top.dut"] on [] {clamp = 2 : i64}
}
