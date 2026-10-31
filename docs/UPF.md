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

UPF compilation is enabled only by `--upf`. Without it, the compiler skips
UPF type projections, Tcl resource discovery, and power-intent elaboration.
Generated designs have no power monitors, guards, supply accesses, retention
copies, or cohort queries, and retain ordinary native scheduling and two-state
specialization. Ordinary dispatch in shared runtime executors tests one dormant
cohort flag, without region or counter bookkeeping until a query is used.
Primed waiters temporarily preserve their caller's region during inline
initialization. Closed generated native loops retain their ordinary scheduling
path.

## Executing UPF and Tcl libraries

IEEE 1801-2018 specifies 68 named Tcl commands: 57 core commands in clauses
6.3–6.59, six cell-definition commands in clauses 7.2–7.7, and five information
model queries in clause 11.1. This count includes legacy/deprecated commands,
and excludes ordinary Tcl commands and the HDL API. The frontend currently
registers 17 core commands, with the option and simulation limits below.

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
`-on_state {name input expression}`, `-on_partial_state {name input expression}`,
and `-error_state {name expression}`
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

Every ON or partial expression reference must be known, even when masked by another
operand or in an inactive state; unused, OFF-only, and ERROR-only controls
do not affect that knownness check (clause 6.22). Multiple true ON states can
contribute the same input without losing power or activating RTL again.
Independent explicit OFF expressions are supported. Simultaneous
true ON/OFF or partial/OFF conditions report a simulation error and corrupt the domain.
Changes that leave aggregate power NORMAL do not activate RTL; restoration
reevaluates level logic, while pending updates from before power loss remain
cancelled (clauses 9.2.2, 9.5.3, and 9.6.7). A true ERROR condition contributes
UNDETERMINED and corrupts the domain; deasserting it permits restoration.
This does not automatically fail the simulation: unlike an OFF/ON conflict,
clause 6.22 specifies the ERROR contribution without requiring a diagnostic.

Partial conditions model current-limited turn-on (clause 6.22, Example 2).
They pass the input state and voltage, degrading FULL_ON to PARTIAL_ON;
other input states keep their state. A full contribution takes priority over a
partial contribution from the same input. ERROR, explicit OFF conflicts, and
unknown ON/partial references take priority over both. An OFF input suppresses
unknown-reference contributions, while ERROR and explicit conflicts still apply.

`set_partial_on_translation FULL_ON` or `set_partial_on_translation OFF`
selects a global interpretation of PARTIAL_ON for supply-set and domain power
state evaluation (clause 6.47). With no command, PARTIAL_ON stays PARTIAL_ON.
Translation affects state references and default ON requirements, preserving
predicate literals, voltage values, physical switch calculations, and raw queries.
Repeated identical settings return the setting; conflicting settings produce a
catchable Tcl error across scopes, loaded files, and repeated `--upf` inputs.

State names are unique across ON, partial, OFF, and ERROR groups. An omitted OFF
condition complements the other state conditions. A partial-only switch can
supply NORMAL power under FULL_ON translation or an explicit partial-state policy.
This slice supports one input supply per switch; general supply-network
resolution remains unsupported.
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
(clause 6.5.1).

Physical port and switch drivers remain distinct when aliases are collapsed;
associations cannot hide an unresolved multiple-source error or bypass switch
output protection. Networks require one supported directional origin with
reachability to their loads. Associated implicit functions do not each invent
another driver (clauses 6.26.2 and 9.1).

## Supply-set power states

`add_power_state` supports deferred supply-set states with `-supply_expr`,
`-simstate NORMAL|CORRUPT|NOT_NORMAL`, `-legal`/`-illegal`, `-update`, and
`-complete` (clauses 6.5 and 9.3.2):

```tcl
add_power_state CORE \
    -state {ON -supply_expr {(power == {FULL_ON 1.0} || power == {FULL_ON 0.8}) && ground == {FULL_ON 0}}} \
    -state {RET -supply_expr {power == {FULL_ON 0.9}} -simstate CORRUPT} \
    -state {OFF -supply_expr {power == OFF}} -complete
```

Supply predicates support state equality, state/nominal-voltage aggregates,
explicit `.state` and `.voltage` fields, real voltage comparisons, parentheses,
and Boolean operators with SystemVerilog precedence (clauses 5.4 and 6.5.4).
`!=` negates the whole aggregate comparison. Stored signed32 microvolts are
converted to binary64 volts before comparison; predicate thresholds are not
rounded using the write conversion. Unsized numeric literals acquire real
voltage semantics beside voltage operands. Numeric-only comparisons and
bitwise operations on unsized numeric literals are diagnosed; explicit
one-bit literals and Boolean predicates support bitwise operators.

Bare function names refer to this set's functions; `./power` selects a local
physical supply named `power`. Physical net/port references are supported,
but a predicate must reference this set's power or ground. Another set's
function is rejected even if electrically equivalent (clause 6.5.6a). Used
functions become required, including wells. The unmodified default ON checks
all required functions for FULL_ON; an explicit ON predicate replaces that
test (clauses 4.5.4.7 and 4.7.4).

Flat fundamental states are exclusive. Overlap, including with the default
ON state, records a simulation error and makes the current state ERROR with
CORRUPT behavior. A uniquely active illegal NORMAL state records an error
while preserving NORMAL behavior (clauses 4.7.3, 6.5.6n, and 9.3.2). Explicit
OFF retains the fallback when no other state is active. `-complete` prevents
adding new fundamental names; gaps still select the predefined OFF state.

A domain combines the policies of its primary handle and its explicitly
associated suppliers. Association traversal is transitive, including through
another domain's primary handle, but that other primary's local catalog stays
local. A supplying auxiliary handle contributes its policy. Merely sharing
physical rails does not create a policy dependency (clauses 6.5.1 and 9.3.2).
NORMAL-to-NORMAL voltage changes preserve RTL evaluations and queued NBAs;
loss of NORMAL corrupts and cancels work, and restoration reevaluates level
logic (clauses 9.5.3 and 9.6.7).

Definitions can be filled incrementally in the original execution scope.
Subsequent commands require `-update`. For first edits of predefined ON/OFF,
both spellings are accepted because clause 6.5.4 examples omit `-update` while
informative Annex E.4.4.3 requires it. ON/OFF simstates are fixed; NOT_NORMAL
acts as CORRUPT in this slice and may later refine to CORRUPT. Other named
states require an explicit simstate when they have an active predicate.
Condition-free drafts are retained but remain inactive.

Each expression is bounded to 64 KiB, 4096 parser nodes, and 256 tree levels;
each catalog to 256 states and 65536 postfix tokens. Predicate updates must
preserve the previous predicate through supported structural refinements.
A bounded consistency check rejects direct Boolean contradictions and
conflicting scalar literal bounds, including aliases resolved by later
bindings. It does not prove general satisfiability, solve transitive relations
between different supplies, or account for every gap in the microvolt grid.
Expansion beyond 256 Boolean branches or 65536 work units is diagnosed.
Caught command errors commit no catalog, history, requiredness, or completion
changes. Delayed errors retain the predicate's Tcl source location.

Power-domain states, hierarchical state refinements, `-logic_expr`,
`-power_expr`, activity-dependent simstates, and power-state control/query
package APIs remain unsupported. In particular, `-logic_expr` requires a
different activation/assertion model and is diagnosed explicitly; it is not
silently combined with a supply predicate (clauses 6.5 and 9.3.2).

## Retention

`set_retention` supports master/slave retention for whole packed integral
registers with one static edge-sensitive writer (IEEE 1801-2018 clauses 6.50,
8.3.2 and 9.7.3, Tables 11/12). The compiler creates typed backing storage
separate from the visible output. RTC True holds the value while unretained
siblings continue clocking. By default primary power loss masks the output;
recovery restores retained data without inventing a clock. Loss of retention
power, or primary loss without RTC True, destroys the backing value. RTC X/Z is
not True. Two-state state corrupts to zero and four-state state to X.

Direct edge-event lists support clocks and asynchronous reset/set in `always`
and `always_ff`. RTC True suppresses every retained write from those events,
while unretained siblings preserve their ordinary RTL behavior. The original
event list remains unchanged: a reset held asserted across RTC release or
primary restoration does not manufacture another reset/clock activation
(clauses 9.6.7/9.7.3). A fresh admitted reset edge can recover corrupt state
without a clock.

`-use_retention_as_primary` powers the output driver from the retention supply
(clause 6.50 and Table 12). Such outputs can remain known while primary power
is OFF and RTC is True, including at startup with anonymous always-on retention
supplies. The data-input receiving supply and functional write guards still
require primary power; unrelated logic in the domain remains inactive while
OFF. Retention supply policies and required ground still apply. Caught failed
Tcl updates leave the flag unchanged; successful updates can add it and
preserve it when omitted. The current isolation mux cannot apply per-output supply filters
for this combination, so effective RET-powered registers with domain isolation
are diagnosed (clause 6.50 Note 2 and clause 6.45). Excluded, nonsequential and
`-no_retention` selections infer no RET-powered driver.

Declaration and untimed initialization stores update backing. Sequential
blocking stores preserve visible program order, including feedback reads.
Nonblocking stores capture their RHS and delay at the original statement,
preserving source order with unretained writes. At actual commit, a pure
observer and captured domain/strategy epochs decide both backing and output
publications together. Pending RTC/loss occurrences reject stale writes
before edge observers see a false known output. A fresh later clock can write
again. Power history follows published supplies; raw switch-control changes
can coalesce before supply-network evaluation (clauses 9.2.2/9.2.3).

Ordinary guarded NBAs use explicit root-relative windows. Selector values and
all ancestor bounds survive captures, CFG forwarding and suspension; partial
and invalid selections retain normal HDL behavior beside retained registers
(IEEE 1800-2023 clauses 7.4.5 and 11.5.1). Their guard is shared per domain,
and assignments enqueue directly without a spawned helper per NBA. The UPF
dialect still has only three operations; storage, guards and scheduling use
the existing simulation dialect.

Native and bytecode execution share the fixed64 guard ABI, including on
wasm32. Installed native AOT plans reject guarded updates; these designs use
the runtime scheduler. Designs without UPF retain the ordinary simulation
path and allocate no power feature state.

Balloon save/restore, latch writers, computed event expressions, multi-event
`iff` lists, partial retained writes, mixed blocking/nonblocking writers of one
retained register, and multiple sequential writers are diagnosed. Retained
references escaping through unsupported helper/CFG/capture forms are also
diagnosed. Ordinary projected captures require one provable persistent root;
references selecting different roots need specialization and are rejected.
A `-no_retention` strategy uses ordinary domain corruption with no backing storage.

The frontend accepts whole-signal and instance `-elements` and
`-exclude_elements`, `-retention_supply`, `-save_signal`, `-restore_signal`,
`-save_condition`, `-restore_condition`, `-retention_condition`, `-no_retention`,
`-use_retention_as_primary`, and `-update`. Signal senses are `high`, `low`,
`posedge`, and `negedge`.
Conditions use the ordinary Boolean expression support and command execution
scope. Level controls retain their distinction from edge controls, including
the trailing-edge event required by clause 6.50. One or both save/restore
signals select balloon style; otherwise a retention condition is required for
master/slave style (clause 9.7.3).

Updates combine explicit include/exclude lists and can complete an earlier
declaration across UPF files. Omitted selection differs from explicit `{}`;
defaults apply after all updates. Failed commands leave declarations,
predefined handles, and associations intact. A strategy and its implicit
handles retain their original execution scope. Required supply functions
propagate across associations (clause 4.5.4.7), while strategy-local state
catalogs remain separate from domain-wide policies.
Updates can fill unspecified fields or repeat an identical definition;
changing an existing trigger or Boolean condition is currently diagnosed as
an unsupported refinement.

Each strategy owns `PD.strategy.primary_supply` and
`PD.strategy.retention_supply` handles. Explicit `-handle`/`-retention_supply`
bindings retain their supplier identity and reject a conflicting second
supplier (clause 6.10); general list-form electrical equivalence is also
supported. Without a supplied retention source, verification uses protected,
anonymous FULL_ON supplies, including ground at zero volts (clauses 6.50 and
9.7.1). Adding downstream consumers preserves these source values; associated
named supplies and concrete bindings retain ordinary supply initialization.

Partial-signal and named-process selectors, legacy retention net options,
`-instance`, and nondefault corruption parameters
produce diagnostics. Explicit `RET_SUP_COR` and `SAV_RES_COR` are accepted;
conflicting parameter pairs are errors. A domain is bounded to 256 strategies
and 65536 condition tokens, and each include/exclude selection to 4096 unique
objects. These implementation limits are catchable Tcl errors.

## Runtime supplies

Supplies start OFF, as specified in clause 9.2.1. Both switched and direct
domains with unmodified ON definitions require all required primary functions,
including power and ground, to be FULL_ON before their logic runs normally
(clause 4.7.4). Ground at zero volts can be FULL_ON;
voltage is not itself an ON predicate. Unassociated primary power and ground
functions have independent roots, accessible as `/top/PD.primary.power` and
`/top/PD.primary.ground`. Associated primary functions alias their supply nets.
Supply initialization precedes HDL declaration initializers: their queries see
the configured initial value, and their successful writes persist into later
processes (clauses 9.2.1 and 11.2.3).

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

The write functions accept runtime strings, return a success bit, and preserve
normal SV argument evaluation, named arguments, and the default 1.0 V for `supply_on`.
Calling them in a constant expression is an error. Calls whose return value
is ignored retain their effects. They lower to simulation storage and scheduler
operations, so generated native, bytecode, and wasm32 simulators need no Tcl,
DPI library, or runtime name registry.

This slice supports absolute UPF-created net/port handles. These start at the
UPF root, such as `/top/VDD`; they are distinct from Tcl's design-relative `/`
(clauses 10.3.2.2.1 and 11.2.3.1.1). A same-name port takes precedence over a
net; use `/top/VDD@upfSupplyNetT` to select the net explicitly, or
`@upfSupplyPortT` for the port (clause 10.3.2.2.3). Eligible connected aliases
update the same root. Resolving names of HDL objects of
`upfSupplyTypeT`/`upfSupplyObjT`, relative HDL supply names, and the remaining
basic property/handle access and control functions are not implemented.

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
that preserves the aggregate NORMAL policy does neither. OFF/ON writes in one activation can coalesce
like other zero-time logic changes.

`--upf-assume-powered-inputs` provides compatibility with the earlier prototype:
writable roots initialize FULL_ON at 1.0 V, or 0 V for primary ground, rather
than OFF. It also retains the prototype's inference of an omitted primary
association from the switch output. Later supply calls still work. It does not
enable nested domain partitions. New designs should explicitly power their
supplies with the standard package functions.

## Reading supply values from SystemVerilog

The standard `get_supply_value(name)` function samples the current state and
voltage of a supply net, port, or function alias (clause 11.2.3.2.6). It accepts
the same absolute UPF handles and class selectors as the write functions,
including protected switch outputs. The return type `upfSupplyTypeT` is the
standard packed struct with a 32-bit `upfSupplyStateE state` field followed by
a signed 32-bit `upfIntegerT voltage` field in microvolts (clauses 11.2.2 and
11.2.4). `state` and `supply_net_type` are the legacy type aliases.

```systemverilog
import UPF::*;
initial begin
  upfSupplyTypeT sample;
  #10;
  sample = get_supply_value("/top/CORE.power");
  if (get_supply_state(sample) != FULL_ON)
    $error("CORE power is not FULL_ON");
  $display("CORE voltage = %f V", get_supply_voltage(sample));
end
```

`get_supply_state`, `get_supply_voltage`, and `get_supply_on_state` operate on
the passed snapshot (clauses 11.2.3.2.7–.9). The voltage accessor returns real
volts. The on-state accessor reports FULL_ON, including FULL_ON at zero volts;
it does not report a domain's effective NORMAL policy. PARTIAL_ON returns true
only with explicit FULL_ON translation; UNDETERMINED returns false (clause 6.47).
The state and voltage accessors preserve the raw snapshot under either setting.

Queries observe root writes immediately, while a computed switch output
retains its published value until ordinary supply propagation runs (clauses
9.2.2–9.2.3 and 11.2.3.2.1). Sampling does not synchronously settle switches.
An earlier snapshot remains unchanged by later writes. Immediate queries do
not create implicit supply subscriptions in HDL processes; actual HDL name and
condition variables retain normal sensitivity. Deferred object mirrors and
their continuous monitoring APIs (clause 11.2.3.4) remain unsupported.

Invalid queries record a nonterminating simulation error. Talos returns
UNDETERMINED with zero microvolts as its recovery value; the standard does not
specify that value. Discarding a result preserves the error, and an unexecuted
query causes no error. The name lookup is nonconstant. State/voltage accessors and
the standard `upf_convert_real_volts_to_int_uvolts` /
`upf_convert_int_uvolts_to_real_volts` helpers are ordinary SV functions that
can be used in constant expressions. `get_supply_on_state` also supports constant
FULL_ON, OFF, and UNDETERMINED snapshots. Its PARTIAL_ON branch requires a runtime
call because Tcl executes after SV constant evaluation; a constant PARTIAL_ON
call produces a diagnostic instead of guessing the later policy.
The conversion helpers follow normal SV
conversions, including nearest-integer rounding with half ties away from zero
(clauses 11.2.3.5.4–.5); they are separate from the checked supply-write API.
Native, bytecode, and wasm32 simulators use the same public types and values.

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
