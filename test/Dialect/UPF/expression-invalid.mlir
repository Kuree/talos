// RUN: talos-opt --split-input-file --verify-diagnostics %s
// IEEE 1801-2018 5.4: malformed normalized expressions must fail at the IR
// boundary, before simulation lowering can consume the postfix stream.
// expected-error @+1 {{control token requires a nonempty path only}}
#bad = #upf.token<opcode = control>
// -----
// expected-error @+1 {{control token requires a nonempty path only}}
#bad = #upf.token<opcode = control, control = "">
// -----
// expected-error @+1 {{constant requires equally typed value/unknown planes}}
#bad = #upf.token<opcode = constant, value = 0 : i8>
// -----
// expected-error @+1 {{constant requires equally typed value/unknown planes}}
#bad = #upf.token<opcode = constant, value = 0 : i8, unknown = 0 : i16>
// -----
// expected-error @+1 {{constant requires signless planes of 1..4096 bits}}
#bad = #upf.token<opcode = constant, value = 0 : si8, unknown = 0 : si8>
// -----
// expected-error @+1 {{constant requires signless planes of 1..4096 bits}}
#bad = #upf.token<opcode = constant, value = 0 : i4097, unknown = 0 : i4097>
// -----
// expected-error @+1 {{fill constant requires one unsigned bit}}
#bad = #upf.token<opcode = constant, value = 0 : i8, unknown = 0 : i8, fill = true>
// -----
// expected-error @+1 {{expression operator cannot carry an operand}}
#bad = #upf.token<opcode = not, control = "top.a">
// -----
// expected-error @+1 {{expression requires 1..4096 postfix tokens}}
#bad = #upf.expression<[]>
// -----
// expected-error @+1 {{expression contains a non-token attribute}}
#bad = #upf.expression<[0 : i32]>
// -----
// expected-error @+1 {{expression postfix stack underflow}}
#bad = #upf.expression<[#upf.token<opcode = not>]>
// -----
// expected-error @+1 {{expression postfix stack underflow}}
#bad = #upf.expression<[#upf.token<opcode = control, control = "top.a">, #upf.token<opcode = and>]>
// -----
#a = #upf.token<opcode = control, control = "top.a">
// expected-error @+1 {{expression must produce exactly one value}}
#bad = #upf.expression<[#a, #a]>
// -----
// expected-error @+1 {{wide Boolean value requires an explicit comparison}}
#bad = #upf.expression<[#upf.token<opcode = constant, value = 2 : i32, unknown = 0 : i32>]>
// -----
// expected-error @+1 {{wide Boolean value requires an explicit comparison}}
#bad = #upf.expression<[#upf.token<opcode = constant, value = 2 : i32, unknown = 0 : i32>, #upf.token<opcode = not>]>
