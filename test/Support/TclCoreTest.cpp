// IEEE 1801-2018 5.1: use a full Tcl interpreter, including proc libraries.
// This test links only Tcl core and exercises its installed scripts without
// module/encoding directories supplied by an unrelated system Tcl installation.
#include <cstdio>
#include <tcl.h>

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  Tcl_FindExecutable(argv[0]);
  Tcl_Interp *interp = Tcl_CreateInterp();
  Tcl_SetVar(interp, "tcl_library", argv[1], TCL_GLOBAL_ONLY);
  int result = Tcl_Init(interp);
  if (result == TCL_OK)
    result = Tcl_EvalEx(interp, R"tcl(
    set auto_path [list [info library]]
    ::tcl::tm::path remove {*}[::tcl::tm::path list]
    proc sum {values} {set n 0; foreach value $values {incr n $value}; return $n}
    set computed [dict create total [sum {1 2 3}]]
    if {[dict get $computed total] != 6} {error "Tcl evaluation failed"}
    if {[string length "電源 😀"] != 4} {error "Unicode processing failed"}
    if {[clock format 0 -format %Y -gmt 1] ne "1970"} {error "core script library failed"}
    if {[llength [glob -nocomplain -directory [info library] encoding/*.enc]]} {
      error "external encoding tables were installed"
    }
    if {[llength [glob -nocomplain -directory [info library] cookiejar*]]} {
      error "non-core cookiejar package was installed"
    }
    if {[llength [info commands winfo]]} {error "unexpected Tk commands"}
  )tcl",
                        -1, TCL_EVAL_GLOBAL);
  if (result != TCL_OK)
    std::fprintf(stderr, "%s\n", Tcl_GetStringResult(interp));
  Tcl_DeleteInterp(interp);
  Tcl_Finalize();
  return result == TCL_OK ? 0 : 1;
}
