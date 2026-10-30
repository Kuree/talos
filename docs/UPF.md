# UPF compiler dependencies

IEEE 1801-2018 clause 5.1 specifies Tcl execution. Talos embeds the static
Tcl 9.0.4 core in the compiler; generated native and wasm32 simulators do not
link Tcl. Tk, tclsh, contributed binary packages, Zipfs and external `.enc`
encoding tables are omitted. UTF-8 strings and identifiers still work. Core
initialization and autoload scripts are installed in `lib/talos/tcl9.0` beside
the compiler's other resources. Tcl and LibTomMath licenses are included in
`docs/third-party/licenses` and installed with the compiler.

Native Linux and macOS compiler builds enable `TALOS_ENABLE_UPF` by default
and build a checksummed Tcl source archive. Set `TALOS_TCL_SOURCE_DIR` to an
extracted Tcl 9.0.4 tree for an offline build. The macOS build forwards the
selected SDK, deployment target and architectures to Tcl's configure script.

Windows compiler builds and cross-host toolchains use a prebuilt static Tcl
9.0.4 prefix through `TALOS_TCL_INSTALL_DIR`. It must contain `include/tcl.h`,
`lib/tcl9.0/init.tcl`, and either `lib/libtcl9.0.a` or the MSVC static library
`lib/tcl90s.lib`. `TALOS_TCL_STATIC_LIBRARY` can select a different archive
name. Match the compiler's architecture and C runtime; a DLL import library
such as `tcl90.lib` is insufficient. Supplying a prefix enables UPF by default
on Windows. No Tcl DLL is needed.

Browser-hosted Emscripten compiler builds default to `TALOS_ENABLE_UPF=OFF`;
they require a compatible prebuilt Tcl prefix to enable it. A native compiler
can elaborate UPF and generate wasm32 simulations with 32-bit pointers and
64-bit simulation handles. Tcl does not cross that target boundary.

## Executing UPF and Tcl libraries

`talos --upf power.upf -emit-slang design.sv -o design.mlir` executes Tcl
after Slang elaboration and emits resolved `upf.domain`, `upf.supply`, and
`upf.supply_set` operations. Supply operations describe shared roots, their
absolute handle aliases, driver permissions, and initial state/voltage values. The
initial command subset includes design scope and object queries, scoped
`load_upf`, power domains, supply nets/ports/sets, set associations, one
control-based power switch per domain, and parent-located output isolation. Unsupported commands and
options produce Tcl errors, which user procedures may handle with `catch`
(IEEE 1801-2018 clause 5.11). The resolved domain retains its UPF declaration's
source location.

Switched domains require an explicit connection between their primary power
function and the switch output. This can use a function handle directly, a
supply-set association, or legacy `set_domain_supply_net`. The `-domain` switch
option selects its creation scope; it does not create that connection (clauses
5.3.3.5, 6.10, 6.22, and 6.43). Unconnected abstract switches are outside this
runtime slice.

Independent domains can contain module hierarchies. Isolation applies at the
upper domain boundary, preserving internal connections (clauses 6.20 and 6.45).
Per-path isolation across multiple boundary instances, collapsed output nets,
nested domain partitions, resolved supply networks, and switch cascades remain
unsupported and produce diagnostics.
Computed input connections are simulated with their parent's power state.
Constants, including parameters and default input values, and level-sensitive
latches reevaluate on restoration. Synchronous external helper calls are
supported after checking their call closure; asynchronous or indirect calls
remain diagnosed. Input expressions owned by an exterior parent remain active.

Power switches accept repeated `-control_port {alias design_object}`,
`-on_state {name input expression}`, and `-error_state {name expression}`
options, plus one optional `-off_state` (clause 6.22). Switch control-port
bindings are scalar integral objects or selected bits. State expressions name
these declared control ports: the specific restriction in clause 6.22 overrides
clause 5.4's general permission to reference HDL objects. Expressions support
parentheses, `!`, `~`, comparisons, `&`, `^`, `|`, `&&`, and `||`, preserving
SystemVerilog precedence, widths, signedness, and four-state intermediates.
For example:

```tcl
create_power_switch SW -domain PD \
    -input_supply_port {vin VDD} -output_supply_port {vout VDD_SW} \
    -control_port {en power_en} -control_port {ready power_ready} \
    -on_state {ON vin {en && ready}} -off_state {OFF {!en}}
```

Every ON expression reference must be known, even when masked by another
operand or in an inactive ON state; unused, OFF-only, and ERROR-only controls
do not affect that knownness check (clause 6.22). Multiple true ON states can
contribute the same input without losing power or activating RTL again.
Independent explicit OFF expressions are supported. Simultaneous
true ON/OFF conditions report a simulation error and corrupt the domain.
Changes that leave aggregate power NORMAL do not activate RTL; restoration
reevaluates level logic, while pending updates from before power loss remain
cancelled (clauses 9.2.2, 9.5.3, and 9.6.7). A true ERROR condition contributes
UNDETERMINED and corrupts the domain; deasserting it permits restoration.
This does not automatically fail the simulation: unlike an OFF/ON conflict,
clause 6.22 specifies the ERROR contribution without requiring a diagnostic.

State names are unique across ON, OFF, and ERROR groups. An omitted OFF
condition complements the other state conditions; a switch with no ON states
never supplies NORMAL power. This slice supports one input supply per switch;
partial-on control and general supply-network resolution remain unsupported.
Sized SV
literals of 1..4096 bits, unbased fill literals, and unsized decimal values
0..2147483647 are accepted; other unsized literals require an explicit width.
Wide values require an explicit comparison at Boolean boundaries, except
literal zero/one, avoiding an implicit coercion beyond clause 5.4's Boolean
definition. Expressions are bounded to 64 KiB, 4096 tokens, and 256 tree levels.
A switch is bounded to 256 states and 65536 total expression tokens;
unsupported syntax and limit violations are catchable Tcl errors.

`--upf-allow-hdl-expressions` enables a Talos extension allowing direct HDL
vector, enum, and selected-object references in switch state expressions.
This preserves the broader expression support while keeping the default
switch name-resolution rules consistent with clause 6.22.

These extended HDL references support static packed bit selections, part selections,
and indexed part selections, including multiple dimensions, ascending and
negative ranges (clauses 5.3.3.2 and 5.4). For example, an ON expression can use
`mode == 2'b10 && controls[7]` or `matrix[1][0:3] == 4'b1010`. Source objects
are limited to 4096 bits; selector indices and widths are constant decimal
integers, with up to 256 element-selection stages. Declared selection types
retain nominal typedef and enum boundaries before storage canonicalization.
Bit-vector bit/part selections are unsigned; selecting a named packed element
retains that element's declared type. A part-select must be the final selector.
Dynamic, out-of-range, reversed, and unpacked
selections produce diagnostics. A switch alias may bind a selected bit;
vector aliases remain unsupported because clause 6.22 does not define vector
range inheritance for the abstract switch's logic ports (10.6.1.11).

The ON knownness check observes only the selected object. `controls[0]`
ignores X/Z elsewhere in the vector, while `controls & 4'b0001` references the
whole vector and therefore detects X/Z in any bit (clause 6.22). The monitor
watches the base object but activates RTL only when aggregate power changes.
Isolation controls currently remain scalar objects.

## Supply sets and associations

`create_supply_set`, `associate_supply_set`, and `create_power_domain -supply`
provide the supply-set connectivity described in clauses 6.26, 6.10, and 6.20:

```tcl
create_supply_net VDD
create_supply_net VSS
create_supply_set CORE -function {power VDD} -function {ground VSS}
create_power_domain PD -elements dut -supply {primary CORE}
```

The equivalent separate association is `associate_supply_set CORE -handle
PD.primary`. A domain always has a primary handle; additional handles can be
declared with `-supply {backup}`. Existing sets and handles require `-update`
when adding function bindings. Updates retain the original execution scope
(clause 8.3.2). An identical or equivalent reference is idempotent; conflicting
bindings produce a Tcl error. Failed declarations leave no partial object.

Associations electrically join corresponding functions and remain effective
when functions are bound later. Lists, transitive links, repeated associations,
and alias cycles are supported. The six standard functions are `power`,
`ground`, `nwell`, `pwell`, `deepnwell`, and `deeppwell`. Unbound functions have
implicit supply roots, initialized OFF. Requiredness is separate from function
existence: primary power and ground are required, but merely binding an unused
well does not make it required for NORMAL operation (clause 4.5.4.7).

Function handles work in supply declarations, connections, switch endpoints,
and legacy primary bindings. For `-function`, concrete nets/ports must be local;
function handles declared in the current scope or descendants are supported.
Other function-handle declaration scopes are diagnosed as unsupported.
Tcl uses names such as `CORE.power` and
`PD.primary.power`; HDL supply functions use absolute names such as
`/top/CORE.power`. Dots delimit UPF object fields, while slashes delimit HDL
instance scopes (clause 5.3.3). Supply sets retain separate identities after
association: electrical equivalence does not inherit power-state definitions
(clause 6.5.1). Explicit power-state definitions remain a subsequent feature.

Physical port and switch drivers remain distinct when aliases are collapsed;
associations cannot hide an unresolved multiple-source error or bypass switch
output protection. Networks require one supported directional origin with
reachability to their loads. Associated implicit functions do not each invent
another driver (clauses 6.26.2 and 9.1).

## Runtime supplies

Supplies start OFF, as specified in clause 9.2.1. Both switched and direct
domains require all primary power and ground functions to be FULL_ON before
their logic runs normally (clause 4.7.4). Ground at zero volts can be FULL_ON;
voltage is not itself an ON predicate. Unassociated primary power and ground
functions have independent roots, accessible as `/top/PD.primary.power` and
`/top/PD.primary.ground`. Associated primary functions alias their supply nets.

When `--upf` is enabled, the compiler provides the SystemVerilog package `UPF`
with `supply_on` and `supply_off` (clauses 11.2.3.3.4 and 11.2.3.3.5), plus
the `upfBooleanT`, `upfStringT`, and `upfRealT` aliases used in their signatures:

```systemverilog
import UPF::*;
initial begin
  if (!supply_on("/top/VDD", 1.0) || !supply_on("/top/VSS", 0.0))
    $fatal(1, "failed to power supplies");
  #10;
  void'(supply_off("/top/VDD"));
end
```

The functions accept runtime strings, return a success bit, and preserve normal
SV argument evaluation, named arguments, and the default 1.0 V for `supply_on`.
Calling them in a constant expression is an error. Calls whose return value
is ignored retain their effects. They lower to simulation storage and scheduler
operations, so generated native, bytecode, and wasm32 simulators need no Tcl,
DPI library, or runtime name registry.

This slice supports absolute UPF-created net/port handles. These start at the
UPF root, such as `/top/VDD`; they are distinct from Tcl's design-relative `/`
(clauses 10.3.2.2.1 and 11.2.3.1.1). A same-name port takes precedence over a
net; use `/top/VDD@upfSupplyNetT` to select the net explicitly, or
`@upfSupplyPortT` for the port (clause 10.3.2.2.3). Eligible connected aliases
update the same root. HDL objects of `upfSupplyTypeT`/`upfSupplyObjT`, relative
HDL supply names, and the remaining package query/control functions are not
implemented.

Unresolved directional networks support one connection per port side:
same-scope LowConn and descendant-port HighConn (clauses 4.5.4.3 and 6.14).
Multiple sources, directional cycles, connected `inout` ports, switch cascades,
shared switch outputs across domains, and switched primary ground produce
diagnostics. A switch output and all its connected aliases are protected from
HDL supply writes (clauses 4.5.1, 9.1, and 11.2.3.3.4/.5).

Unknown/protected names and invalid voltages return zero and record a
nonterminating simulation error without changing a supply. Unexecuted calls
produce no runtime error. Voltages use signed 32-bit integer microvolts with
SV rounding to the nearest integer; finite zero and negative voltages are
accepted, while NaN, infinities, and unrepresentable results are rejected
(clauses 11.2.2 and 11.2.3.5.4). `supply_off` writes OFF and zero volts, following
the specific function definition in clause 11.2.3.3.5 rather than the differing
general description in clause 9.3.1. State and voltage share one atomic
simulation storage value; the representation is identical on wasm32.

Supply changes follow ordinary HDL scheduling (clause 9.2.3). A settled OFF
transition corrupts state and cancels prior pending updates; restoration
reevaluates level logic without inventing clock edges. A voltage-only change
that remains FULL_ON does neither. OFF/ON writes in one activation can coalesce
like other zero-time logic changes.

`--upf-assume-powered-inputs` provides compatibility with the earlier prototype:
writable roots initialize FULL_ON at 1.0 V, or 0 V for primary ground, rather
than OFF. It also retains the prototype's inference of an omitted primary
association from the switch output. Later supply calls still work. It does not
enable nested domain partitions. New designs should explicitly power their
supplies with the standard package functions.

User Tcl libraries can be sourced or imported with standard Tcl packages
(IEEE 1801-2018 clause 5.1):

```tcl
lappend auto_path [file join [file dirname [info script]] my_libraries]
package require MyPowerHelpers 1.0
::my_power_helpers::declare_domains
```

Provide the package's usual `pkgIndex.tcl` and Tcl scripts in that directory.
These libraries execute in the same interpreter and can call the registered
UPF commands. Binary Tcl extensions are not bundled with Talos; any supplied
extension must match Tcl 9.0 and the compiler host's architecture.
