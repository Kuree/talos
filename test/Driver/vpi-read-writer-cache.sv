// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -shared -fPIC -nostdlib -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: talos -O3 --vpi=read %t/top.sv %t/client.so -o %t/native && %t/native | FileCheck %s
// RUN: talos -O3 --execution-tier=bytecode --vpi=read %t/top.sv %t/client.so -o %t/bc && %t/bc | FileCheck %s
// CHECK: 65 initial subscriptions, 32 surviving, 33 reattached
//--- top.sv
module counter(input bit clk);
  timeunit 1ns; timeprecision 1ns;
  bit [7:0] q;
  always @(posedge clk) q <= q + 1;
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  always #1 clk = !clk;
  for (genvar i = 0; i < 65; ++i) begin : lanes
    counter c(clk);
  end
  initial #10 $finish;
endmodule
//--- client.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
enum { lanes = 65 };
static struct lane {
  vpiHandle value, watch;
  unsigned calls;
} state[lanes];
static PLI_INT32 change(p_cb_data cb) {
  struct lane *lane = (struct lane *)cb->user_data;
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(lane->value, &value);
  assert(value.value.integer == cb->value->value.integer);
  assert(value.value.integer == (int)((cb->time->low + 1) / 2));
  ++lane->calls;
  return 0;
}
static void attach(struct lane *lane) {
  s_vpi_time time = {.type = vpiSimTime};
  s_vpi_value value = {.format = vpiIntVal};
  s_cb_data cb = {.reason = cbValueChange, .cb_rtn = change, .obj = lane->value,
                  .time = &time, .value = &value, .user_data = (PLI_BYTE8 *)lane};
  lane->watch = vpi_register_cb(&cb);
  assert(lane->watch);
}
static PLI_INT32 boundary(p_cb_data cb) {
  for (unsigned i = 0; i < lanes; i += 2) {
    if (cb->time->low == 2)
      assert(vpi_remove_cb(state[i].watch));
    else
      attach(&state[i]);
  }
  return 0;
}
static PLI_INT32 start(p_cb_data cb) {
  for (unsigned i = 0; i != lanes; ++i) {
    char name[64];
    snprintf(name, sizeof(name), "top.lanes[%u].c.q", i);
    state[i].value = vpi_handle_by_name((PLI_BYTE8 *)name, 0);
    assert(state[i].value);
    attach(&state[i]);
  }
  for (unsigned t = 2; t <= 6; t += 4) {
    s_vpi_time time = {.type = vpiSimTime, .low = t};
    s_cb_data sync = {.reason = cbReadOnlySynch, .cb_rtn = boundary, .time = &time};
    assert(vpi_register_cb(&sync));
  }
  return 0;
}
static PLI_INT32 done(p_cb_data cb) {
  for (unsigned i = 0; i != lanes; ++i)
    assert(state[i].calls == ((i & 1) ? 5 : 3));
  puts("65 initial subscriptions, 32 surviving, 33 reattached");
  return 0;
}
static void startup(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = done;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {startup, 0};
