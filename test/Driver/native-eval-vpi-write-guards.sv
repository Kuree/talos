// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -fPIC -shared -nostdlib %t/plugin.c -I%resource_dir/include -o %t/plugin.so
// RUN: talos -O3 --vpi=full --native-scheduler=eval %t/design.sv %t/plugin.so -o %t/eval
// RUN: not %t/eval > %t/eval.out 2>&1
// RUN: FileCheck %s < %t/eval.out

// Each generated owner checks its current write certificate. A force must
// still override every subsequent procedural assignment, release must restore
// later assignments, and X writes must revoke the separate knownness proof
// (LRM 10.6.2, 38.34, 6.3.1). A late cbError also writes during a runtime
// boundary; no clean certificate may be cached across that callback (38.36.3).
// CHECK: passive 12
// CHECK-NEXT: forced 84
// CHECK-NEXT: held 84
// CHECK-NEXT: released 1d
// CHECK-NEXT: unknown xx
// CHECK-NEXT: recovered 13
// CHECK: callback 44
// CHECK-NEXT: resumed 14

//--- design.sv
module ranked_vpi;
  bit clk = 0;
  logic [7:0] seed = 0;
  logic [7:0] w0, w1, w2, w3, w4, w5, w6, w7;
  always_comb w0 = seed + 8'd1;
  always_comb w1 = w0 + 8'd1;
  always_comb w2 = w1 + 8'd1;
  always_comb w3 = w2 + 8'd1;
  always_comb w4 = w3 + 8'd1;
  always_comb w5 = w4 + 8'd1;
  always_comb w6 = w5 + 8'd1;
  always_comb w7 = w6 + 8'd1;
  import "DPI-C" function int mutate(input int action);
  always #2 clk = ~clk;
  always @(posedge clk) seed <= seed + 8'd1;
  initial begin
    #41 $display("passive %h", w7);
    if (mutate(1)) $fatal(1, "force failed");
    #2 $display("forced %h", w7);
    #36 $display("held %h", w7);
    if (mutate(2)) $fatal(1, "release failed");
    #4 $display("released %h", w7);
    if (mutate(3)) $fatal(1, "X write failed");
    #2 $display("unknown %h", w7);
    if (mutate(4)) $fatal(1, "recovery write failed");
    #2 $display("recovered %h", w7);
    if (mutate(5)) $fatal(1, "callback registration failed");
    $error("late callback write");
    #2 $display("callback %h", w7);
    if (mutate(2)) $fatal(1, "callback release failed");
    #2 $display("resumed %h", w7);
    $finish;
  end
endmodule

//--- plugin.c
#include "vpi_user.h"

static int put(const char *name, int bits, int unknown, int mode) {
  vpiHandle handle = vpi_handle_by_name((PLI_BYTE8 *)name, 0);
  if (!handle) return -1;
  s_vpi_vecval vector = {bits, unknown};
  s_vpi_value value = {vpiVectorVal};
  value.value.vector = &vector;
  vpi_put_value(handle, &value, 0, mode);
  vpi_release_handle(handle);
  return vpi_chk_error(0) ? -1 : 0;
}

static vpiHandle error_callback;
static PLI_INT32 on_error(p_cb_data data) {
  (void)data;
  vpi_remove_cb(error_callback);
  return put("$root.ranked_vpi.w3", 0x40, 0, vpiForceFlag);
}

int mutate(int action) {
  if (action == 5) {
    static s_cb_data callback = {0};
    callback.reason = cbError;
    callback.cb_rtn = on_error;
    error_callback = vpi_register_cb(&callback);
    return error_callback ? 0 : -1;
  }
  if (action <= 2)
    return put("$root.ranked_vpi.w3", 0x80, 0,
               action == 1 ? vpiForceFlag : vpiReleaseFlag);
  return put("$root.ranked_vpi.seed", 10, action == 3 ? 0xff : 0, vpiNoDelay);
}

void (*vlog_startup_routines[])(void) = {0};
