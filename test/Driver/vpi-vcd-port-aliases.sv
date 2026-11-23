// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -nostdlib -shared -fPIC -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: cd %t && talos -O3 --vpi=read top.sv client.so -o sim && ./sim | FileCheck %s --check-prefix=LIVE && FileCheck %s --check-prefix=SHARED < ports.vcd
// RUN: cd %t && talos -O3 --execution-tier=bytecode --vpi=read top.sv client.so -o bc && ./bc | FileCheck %s --check-prefix=LIVE
// RUN: cd %t && FileCheck %s --check-prefix=SHARED < ports.vcd
// RUN: cd %t && talos -O3 --vpi=read -Wno-multiple-always-assigns +define+FINAL_WRITE top.sv client.so -o final && ./final && FileCheck %s --check-prefix=FINAL < ports.vcd
// RUN: cd %t && env STOP_EARLY=1 ./sim | FileCheck %s --check-prefix=STOP
// RUN: cd %t && FileCheck %s --check-prefix=STOPWAVE < ports.vcd
// STOP: finish q=1 d=0
// LIVE: live q=1 d=0
// SHARED: $var wire 4 [[NET:[^ ]+]] pad [3:0] $end
// SHARED: $var wire 4 [[NET]] outside [3:0] $end
// FINAL: $var reg 4 [[D:[^ ]+]] d [3:0] $end
// FINAL: $var reg 4 [[Q:[^ ]+]] q [3:0] $end
// FINAL: #12
// FINAL-NEXT: b1111 [[Q]]
// FINAL-NOT: b1111 [[D]]
// STOPWAVE: $var reg 4 [[D:[^ ]+]] d [3:0] $end
// STOPWAVE: $var reg 4 [[Q:[^ ]+]] q [3:0] $end
// STOPWAVE: #5
// STOPWAVE-NOT: b1 [[D]]
// STOPWAVE: b1 [[Q]]
// STOPWAVE-NOT: b1 [[D]]
//--- top.sv
module leaf(input logic clk, input logic [3:0] d, output logic [3:0] data_o, inout wire [3:0] pad);
  always_ff @(posedge clk) data_o <= d;
endmodule
module top;
  bit clk;
  logic [3:0] q = 0, r;
  wire [3:0] outside;
  assign outside = q;
  leaf u(clk, q, r, outside);
  always #5 clk = !clk;
  always_ff @(posedge clk) q <= q + 1;
`ifdef FINAL_WRITE
  final q = 15;
`endif
  initial begin
    $dumpfile("ports.vcd");
    $dumpvars(0, top);
    // Fix the header before the first sample to inspect compiler-proven aliases.
    $dumpflush;
    #12 $finish;
  end
endmodule
//--- client.c
#include "vpi_user.h"
#include <assert.h>
#include <stdlib.h>
static vpiHandle sink, source;
static int stop_early;
static PLI_INT32 changed(p_cb_data cb) {
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(sink, &value);
  if (stop_early && cb->value->value.integer == 1) assert(vpi_control(vpiFinish, 0));
  vpi_printf("live q=%d d=%d\n", cb->value->value.integer, value.value.integer);
  return 0;
}
static PLI_INT32 finish(p_cb_data unused) {
  if (stop_early) {
    s_vpi_value v = {.format = vpiIntVal};
    vpi_get_value(source, &v);
    int q = v.value.integer;
    vpi_get_value(sink, &v);
    vpi_printf("finish q=%d d=%d\n", q, v.value.integer);
  }
  return 0;
}
static PLI_INT32 start(p_cb_data unused) {
  vpiHandle q = vpi_handle_by_name((PLI_BYTE8 *)"top.q", 0);
  source = q;
  stop_early = getenv("STOP_EARLY") != 0;
  sink = vpi_handle_by_name((PLI_BYTE8 *)"top.u.d", 0);
  assert(q && sink && !vpi_compare_objects(q, sink));
  s_vpi_time t = {.type = vpiSimTime};
  s_vpi_value v = {.format = vpiIntVal};
  s_cb_data cb = {.reason = cbValueChange, .cb_rtn = changed, .obj = q,
                  .time = &t, .value = &v};
  assert(vpi_register_cb(&cb));
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
