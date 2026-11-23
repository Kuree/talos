// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -fPIC -shared -nostdlib -I%resource_dir/include %t/sub.c -o %t/sub.so
// RUN: talos -O3 --vpi=read %t/top.sv %t/sub.so -o %t/native
// RUN: env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/native > %t/out 2> %t/diag && FileCheck %s < %t/out && FileCheck %s --check-prefix=ROUTE < %t/diag
// RUN: talos -O3 --vpi=read --execution-tier=bytecode %t/top.sv %t/sub.so -o %t/bc && %t/bc | diff -u %t/out -
// RUN: talos -O3 --vpi=read --two-state %t/top.sv %t/sub.so -o %t/two && %t/two | diff -u %t/out -
// RUN: %t/native +clock > %t/clock && FileCheck %s --check-prefix=CLOCK < %t/clock
// RUN: %t/bc +clock | diff -u %t/clock -
// CLOCK: clock changes=36 background=18 independent=30
// IEEE 1800-2023 4.10, 38.36.1. Attach after startup, observe both NBAs
// to one register in the same slot, then release the last watch and reattach.
// ROUTE-COUNT-2: talos-vpi-watch writers=1 actors={{[2-9][0-9]*}} native_owner_checks={{[1-9][0-9]*}}
// CHECK: changed 15 2
// CHECK-NEXT: changed 15 3
// CHECK-NEXT: changed 35 6
// CHECK-NEXT: changed 35 7
// CHECK-NEXT: final 18 35

//--- top.sv
module oscillator;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  bit [7:0] count;
  always #3 clk = !clk;
  always @(posedge clk) count <= count + 1;
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  bit [7:0] watched, background, stamp;
  oscillator independent();
  always #5 clk = !clk;
  always @(posedge clk) begin
    watched <= background << 1;
    stamp <= background;
    watched <= (background << 1) + 1;
  end
  always @(posedge clk) background <= background + 1;
  initial #181 $finish;
endmodule

//--- sub.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static vpiHandle target, other, stamp, registration;
static int count, steps, clock_mode;
static int read_int(vpiHandle object) {
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(object, &value);
  return value.value.integer;
}
static PLI_INT32 change(p_cb_data cb) {
  assert(cb->value->value.integer == read_int(target));
  if (clock_mode) {
    assert(cb->time->low == 5 * (count + 1));
    assert(cb->value->value.integer == ((count + 1) & 1));
  } else {
    // The intervening NBA becomes visible between the two updates of watched.
    assert(read_int(stamp) == (cb->value->value.integer >> 1) -
                                  !(cb->value->value.integer & 1));
    printf("changed %u %d\n", cb->time->low, cb->value->value.integer);
  }
  ++count;
  return 0;
}
static PLI_INT32 sync_cb(p_cb_data);
static void schedule(unsigned delay) {
  s_vpi_time time = {.type = vpiSimTime, .low = delay};
  s_cb_data cb = {.reason = cbReadOnlySynch, .time = &time, .cb_rtn = sync_cb};
  assert(vpi_register_cb(&cb));
}
static PLI_INT32 sync_cb(p_cb_data cb) {
  if (++steps & 1) {
    s_vpi_value value = {.format = vpiIntVal};
    s_vpi_time time = {.type = vpiSimTime};
    s_cb_data reg = {.reason = cbValueChange,
                     .obj = target,
                     .value = &value,
                     .time = &time,
                     .cb_rtn = change};
    registration = vpi_register_cb(&reg);
    assert(registration);
  } else {
    assert(vpi_remove_cb(registration));
  }
  if (steps < 4)
    schedule(10);
  return 0;
}
static PLI_INT32 start(p_cb_data cb) {
  s_vpi_vlog_info args;
  assert(vpi_get_vlog_info(&args));
  for (int i = 0; i < args.argc; ++i)
    clock_mode |= strcmp(args.argv[i], "+clock") == 0;
  target = vpi_handle_by_name(
      (PLI_BYTE8 *)(clock_mode ? "top.clk" : "top.watched"), 0);
  other = vpi_handle_by_name((PLI_BYTE8 *)"top.background", 0);
  stamp = vpi_handle_by_name((PLI_BYTE8 *)"top.stamp", 0);
  assert(target && other && stamp);
  if (clock_mode) {
    s_vpi_value value = {.format = vpiIntVal};
    s_vpi_time time = {.type = vpiSimTime};
    s_cb_data reg = {.reason = cbValueChange,
                     .obj = target,
                     .value = &value,
                     .time = &time,
                     .cb_rtn = change};
    registration = vpi_register_cb(&reg);
    assert(registration);
  } else
    schedule(10);
  return 0;
}
static PLI_INT32 finish(p_cb_data cb) {
  vpiHandle independent =
      vpi_handle_by_name((PLI_BYTE8 *)"top.independent.count", 0);
  assert(independent && read_int(independent) == 30);
  if (clock_mode) {
    assert(count == 36 && steps == 0 && read_int(other) == 18);
    printf("clock changes=%d background=%d independent=%d\n", count,
           read_int(other), read_int(independent));
  } else {
    assert(count == 4 && steps == 4);
    printf("final %d %d\n", read_int(other), read_int(target));
  }
  return 0;
}
static void install(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = finish;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {install, 0};
