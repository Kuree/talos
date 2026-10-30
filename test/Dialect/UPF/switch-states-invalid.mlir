// RUN: talos-opt --split-input-file --verify-diagnostics %s
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
// expected-error @+1 {{switch state requires a nonempty name}}
#bad = #upf.state<name = "", condition = #one>
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] power @switched on [#state, #state] {input = @rail}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] power @switched on [#state] {input = @rail, off = #state}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] power @switched on [#state] {input = @rail, errors = [#state]}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] power @switched on [] {input = @rail, off = #state, errors = [#state]}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
module {
  upf.supply @rail names ["/top/VDD"] writable = true
  upf.supply @switched names ["/top/SW"] writable = false
  // expected-error @+1 {{attribute 'on' failed to satisfy constraint}}
  upf.domain @wrong elements ["top.dut"] power @switched on [#one] {input = @rail}
}
