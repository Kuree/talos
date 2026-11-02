// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -fPIC -shared -nostdlib %t/plugin.c -I%resource_dir/include -Wl,-soname,libforce.so -o %t/libforce.so
// RUN: cd %t && talos -O0 --vpi=full design.sv libforce.so -o simulator
// RUN: %t/simulator | FileCheck %s
// RUN: not talos --vpi=full --native-scheduler=aot --static-specialization=off %t/design.sv -o %t/rejected 2>&1 | FileCheck %s --check-prefix=REJECTED

// IEEE 1800-2023 38.34: a VPI force can precede the first process. Below -O2 there
// are no static specialization plans to keep a generated coordinator coherent with
// it, so the automatic scheduler is the generic one and asking for AOT is an error.

// CHECK: seed=7 total=14
// REJECTED: error: native AOT scheduling with a writable VPI requires static specialization

//--- plugin.c
#include "vpi_user.h"
static PLI_INT32 end_compile(p_cb_data callback) {
  vpiHandle seed = vpi_handle_by_name((PLI_BYTE8 *)"$root.top.seed", 0);
  s_vpi_value value = {vpiIntVal};
  value.value.integer = 7;
  vpi_put_value(seed, &value, 0, vpiForceFlag);
  vpi_release_handle(seed);
  return 0;
}
static void start(void) {
  static s_cb_data callback = {cbEndOfCompile, end_compile};
  vpi_register_cb(&callback);
}
void (*vlog_startup_routines[])(void) = {start, 0};

//--- design.sv
module top;
  bit clock;
  int seed = 41;
  int total;
  always @(posedge clock)
    total <= total + seed;
  initial begin
    #1 clock = 1;
    #1 clock = 0;
    #1 clock = 1;
    #1 $display("seed=%0d total=%0d", seed, total);
    $finish;
  end
endmodule
