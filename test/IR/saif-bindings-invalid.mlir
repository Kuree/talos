// RUN: talos-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{saif.output requires a nonempty file path}}
module attributes {saif.output = ""} {}

// -----
// expected-error @+1 {{unknown SAIF attribute}}
module attributes {saif.unknown = unit} {}

// -----
// expected-error @+1 {{saif.bindings requires at most 1048576 bindings}}
module attributes {saif.output = "out.saif", saif.bindings = "wrong"} {}

// -----
// expected-error @+1 {{saif.bindings requires saif.output}}
module attributes {saif.bindings = []} {}

// -----
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "q">, port = false, initial = 2>
// expected-error @+1 {{duplicate SAIF mapped output signal}}
module attributes {saif.output = "out.saif", saif.bindings = [#q, #q]} {}

// -----
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "q">, port = true, initial = 2, virtualType = "seq">
#r = #saif.binding<sourceId = 1, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "r">, port = true, initial = 2, virtualType = "other">
// expected-error @+1 {{inconsistent SAIF virtual instance type}}
module attributes {saif.output = "out.saif", saif.bindings = [#q, #r]} {}

// -----
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "q">, port = true, initial = 2, virtualType = "seq">
#r = #saif.binding<sourceId = 1, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "r">, port = false, initial = 2>
// expected-error @+1 {{SAIF virtual instance may contain only ports}}
module attributes {saif.output = "out.saif", saif.bindings = [#q, #r]} {}

// -----
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "q">, port = true, initial = 2, virtualType = "seq">
#r = #saif.binding<sourceId = 1, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">, #saif.identifier<name = "child">]>, signal = <name = "r">, port = true, initial = 2>
// expected-error @+1 {{SAIF virtual instance cannot have child instances}}
module attributes {saif.output = "out.saif", saif.bindings = [#q, #r]} {}

// -----
#r = #saif.binding<sourceId = 1, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">, #saif.identifier<name = "child">]>, signal = <name = "r">, port = true, initial = 2>
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 0, instance = <[#saif.identifier<name = "top">]>, signal = <name = "q">, port = true, initial = 2, virtualType = "seq">
// expected-error @+1 {{SAIF virtual instance may contain only ports}}
module attributes {saif.output = "out.saif", saif.bindings = [#r, #q]} {}

// -----
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 2147483648, instance = <[#saif.identifier<name = "top">]>, signal = <name = "q">, port = false, initial = 2>
// expected-error @+1 {{invalid SAIF observation binding}}
module attributes {saif.output = "out.saif", saif.bindings = [#q]} {}

// -----
#q = #saif.binding<sourceId = 0, sourceIsNet = false, sourceLow = 0, instance = <[1 : i32]>, signal = <name = "q">, port = false, initial = 2>
// expected-error @+1 {{path requires 1..4096 identifier components}}
module attributes {saif.output = "out.saif", saif.bindings = [#q]} {}

// -----
// expected-error @+1 {{SAIF collection attributes belong on a module}}
func.func @f() attributes {saif.output = "out.saif"} { return }
