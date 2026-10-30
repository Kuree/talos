// RUN: talos-opt --split-input-file --verify-diagnostics %s
// expected-error @+1 {{control selection must fit a source of 1..4096 bits}}
#bad = #upf.token<opcode = control, control = "top.a", width = 0>
// -----
// expected-error @+1 {{control selection must fit a source of 1..4096 bits}}
#bad = #upf.token<opcode = control, control = "top.a", sourceWidth = 0>
// -----
// expected-error @+1 {{control selection must fit a source of 1..4096 bits}}
#bad = #upf.token<opcode = control, control = "top.a", width = 9, sourceWidth = 8>
// -----
// expected-error @+1 {{control selection must fit a source of 1..4096 bits}}
#bad = #upf.token<opcode = control, control = "top.a", sourceWidth = 8, offset = 8>
// -----
// expected-error @+1 {{control selection must fit a source of 1..4096 bits}}
#bad = #upf.token<opcode = control, control = "top.a", width = 3, sourceWidth = 8, offset = 6>
// -----
// expected-error @+1 {{control selection must fit a source of 1..4096 bits}}
#bad = #upf.token<opcode = control, control = "top.a", sourceWidth = 4097>
// -----
// expected-error @+1 {{only control tokens carry selection dimensions}}
#bad = #upf.token<opcode = constant, value = 0 : i8, unknown = 0 : i8, width = 8>
// -----
// expected-error @+1 {{only control tokens carry selection dimensions}}
#bad = #upf.token<opcode = not, offset = 1>
// -----
// expected-error @+1 {{wide Boolean value requires an explicit comparison}}
#bad = #upf.expression<[#upf.token<opcode = control, control = "top.a", width = 8, sourceWidth = 8>]>
