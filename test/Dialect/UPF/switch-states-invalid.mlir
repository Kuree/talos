// RUN: talos-opt --split-input-file --verify-diagnostics %s
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
// expected-error @+1 {{switch state requires a nonempty name}}
#bad = #upf.state<name = "", condition = #one>
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] on [#state, #state]
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] on [#state] {off = #state}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] on [#state] {errors = [#state]}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
#state = #upf.state<name = "S", condition = #one>
module {
  // expected-error @+1 {{duplicate power-switch state name}}
  upf.domain @duplicate elements ["top.dut"] on [] {off = #state, errors = [#state]}
}
// -----
#one = #upf.expression<[#upf.token<opcode = constant, value = true, unknown = false>]>
module {
  // expected-error @+1 {{attribute 'on' failed to satisfy constraint}}
  upf.domain @wrong elements ["top.dut"] on [#one]
}
