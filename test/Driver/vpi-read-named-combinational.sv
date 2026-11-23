// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -fPIC -nostdlib -shared -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: talos -O3 --vpi=read --mlir-timing +define+FOREIGN %t/top.sv %t/client.so -o %t/native 2>%t/plan && FileCheck %s --check-prefix=PLAN < %t/plan
// RUN: %t/native | FileCheck %s --check-prefix=QUIET
// RUN: env WATCH=1 %t/native >%t/observed && FileCheck %s --check-prefix=WATCH < %t/observed
// RUN: talos -O0 --execution-tier=bytecode --vpi=read %t/top.sv %t/client.so -o %t/vm && env WATCH=1 %t/vm | diff -u %t/observed -
// The context import runs in another process. The named loop's activation
// needs its source frame only when a subscriber observes its writes.
// PLAN: talos read eval private controls: body={{.*}} count={{[1-9][0-9]*}}
// QUIET: updates=0
// WATCH: updates=4
//--- top.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  bit [31:0] src, q;
`ifdef FOREIGN
  import "DPI-C" context function int probe();
  export "DPI-C" function parameter_query;
  function int parameter_query(); return 7; endfunction
`endif
  always_comb begin
    for (integer i = 0; i < 4; ++i) begin : lane
      q[8*i +: 8] = src[8*i +: 8];
    end
  end
  initial begin
    #1;
`ifdef FOREIGN
    if (probe() != 0) $fatal;
`endif
    #2 src = 32'h44332211;
    #2 if (q !== src) $fatal;
    $finish;
  end
endmodule
//--- client.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static vpiHandle q;
static unsigned updates;
int probe(void) {
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(q, &value);
  return value.value.integer;
}
static PLI_INT32 change(p_cb_data cb) {
  static const unsigned expected[] = {0x11, 0x2211, 0x332211, 0x44332211};
  assert(updates < 4 && cb->value->value.integer == (int)expected[updates]);
  assert(probe() == (int)expected[updates]);
  ++updates;
  return 0;
}
static PLI_INT32 start(p_cb_data unused) {
  q = vpi_handle_by_name((PLI_BYTE8 *)"top.q", 0);
  assert(q);
  if (getenv("WATCH")) {
    s_vpi_time time = {.type = vpiSimTime};
    s_vpi_value value = {.format = vpiIntVal};
    s_cb_data cb = {.reason = cbValueChange, .obj = q, .cb_rtn = change,
                    .time = &time, .value = &value};
    assert(vpi_register_cb(&cb));
  }
  return 0;
}
static PLI_INT32 finish(p_cb_data unused) {
  assert(probe() == 0x44332211);
  printf("updates=%u\n", updates);
  return 0;
}
static void boot(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = finish;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {boot, 0};
