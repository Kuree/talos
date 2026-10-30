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
after Slang elaboration and emits resolved `upf.domain` operations. The
initial command subset includes design scope and object queries, scoped
`load_upf`, power domains, supply nets/ports, one control-based power switch,
and parent-located output isolation. Unsupported commands and options produce
Tcl errors, which user procedures may handle with `catch` (IEEE 1801-2018
clause 5.11). The resolved domain retains its UPF declaration's source location.

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
