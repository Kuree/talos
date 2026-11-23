// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -nostdlib -shared -fPIC -I%resource_dir/include %t/watch.c -o %t/watch.so
// RUN: talos -O3 --vpi=read %t/top.sv %t/watch.so -o %t/native
// RUN: env SIGNAL=top.a %t/native | FileCheck %s
// RUN: env SIGNAL=top.b %t/native | FileCheck %s
// RUN: talos -O0 --execution-tier=bytecode --vpi=read %t/top.sv %t/watch.so -o %t/bytecode
// RUN: env SIGNAL=top.b %t/bytecode | FileCheck %s
// CHECK: changes=3 final=3

//--- top.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  bit [7:0] a, b;
  always #5 clk = !clk;
  always_ff @(posedge clk) a <= a + 1;
  always @(posedge clk) b <= b + 1;
  initial #26 $finish;
endmodule

//--- watch.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static vpiHandle watched;
static int count;
static PLI_INT32 changed(p_cb_data cb) {
  ++count;
  assert(cb->time->low == 5 + 10 * (count - 1));
  assert(cb->value->value.integer == count);
  return 0;
}
static PLI_INT32 sync_cb(p_cb_data cb) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(watched, &v);
  assert(cb->time->low == 15 && count == 2 && v.value.integer == 2);
  return 0;
}
static PLI_INT32 start(p_cb_data cb) {
  watched = vpi_handle_by_name((PLI_BYTE8 *)getenv("SIGNAL"), NULL);
  assert(watched);
  s_vpi_time t = {.type = vpiSimTime};
  s_vpi_value v = {.format = vpiIntVal};
  s_cb_data change = {.reason = cbValueChange, .cb_rtn = changed,
                      .obj = watched, .time = &t, .value = &v};
  assert(vpi_register_cb(&change));
  t.low = 15;
  s_cb_data sync = {.reason = cbReadOnlySynch, .cb_rtn = sync_cb, .time = &t};
  assert(vpi_register_cb(&sync));
  return 0;
}
static PLI_INT32 finish(p_cb_data cb) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(watched, &v);
  assert(count == 3 && v.value.integer == 3);
  printf("changes=%d final=%d\n", count, v.value.integer);
  return 0;
}
static void startup(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = finish;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {startup, NULL};
