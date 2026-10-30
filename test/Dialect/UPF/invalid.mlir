// RUN: talos-opt --split-input-file --verify-diagnostics %s
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{requires domain elements}}
  upf.domain @empty elements [] power @switched on [] {input = @rail}
}
// -----
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{domain element must not be empty}}
  upf.domain @empty_element elements [""] power @switched on [] {input = @rail}
}
// -----
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{isolation control must not be empty}}
  upf.domain @empty_isolation elements ["top.dut"] power @switched on [] {input = @rail, isolation_control = ""}
}
// -----
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{isolation clamp must be zero or one}}
  upf.domain @clamp elements ["top.dut"] power @switched on [] {input = @rail, clamp = 2 : i64}
}
