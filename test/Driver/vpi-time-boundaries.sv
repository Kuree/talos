// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -fPIC -shared -nostdlib -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: talos -O3 --vpi=read %t/top.sv %t/client.so -o %t/sim && %t/sim | FileCheck %s
// RUN: talos -O0 --vpi=read --execution-tier=bytecode %t/top.sv %t/client.so -o %t/bc && %t/bc | FileCheck %s
// RUN: talos -O3 --vpi=full %t/top.sv %t/client.so -o %t/full && %t/full | FileCheck %s
// RUN: talos -O3 --vpi=read %t/idle.sv %t/client.so -o %t/idle && %t/idle | FileCheck %s --check-prefix=IDLE
// RUN: talos -O3 --vpi=read %t/clock.sv %t/client.so -o %t/clock && env CLOCK_SYNC=nba %t/clock | FileCheck %s --check-prefix=CLOCK-NBA
// RUN: env CLOCK_SYNC=end %t/clock | FileCheck %s --check-prefix=CLOCK-END
// CLOCK-NBA: at edge t=5 clk=1 q=0
// CLOCK-NBA-NEXT: at edge t=15 clk=1 q=1
// CLOCK-END: at edge t=5 clk=1 q=1
// CLOCK-END-NEXT: at edge t=15 clk=1 q=2
// IDLE: start
// IDLE-NEXT: last-slot t=3 value=7
// IDLE-NEXT: finish
// IEEE 1800-2023 Table 4-1 and 38.36.2-3. Pre-Active sees the previous
// value, Pre-NBA sees the blocking write, and Pre-Postponed sees the NBA.
// CHECK: end-compile
// CHECK-NEXT: start
// CHECK-NEXT: next t=2 value=1
// CHECK-NEXT: begin t=2 value=1
// CHECK-NEXT: nested-begin t=2 value=1
// CHECK-NEXT: timer t=2 value=1
// CHECK-NEXT: nba t=2 value=2
// CHECK-NEXT: end-slot t=2 value=3
// CHECK-NEXT: read-only t=2 value=3
// CHECK-NEXT: next t=5 value=3
// CHECK-NEXT: otherwise-empty t=7 value=4
// CHECK-NEXT: finish

//--- top.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  int value;
  initial begin
    value = 1;
    #2 value = 2;
    value <= 3;
    #3 value = 4;
    #4 $finish;
  end
endmodule

//--- clock.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  int q;
  always #5 clk = !clk;
  always @(posedge clk) q <= q + 1;
  initial #22 $finish;
endmodule

//--- client.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static vpiHandle variable, cancelled;
static PLI_INT32 call(p_cb_data cb);
static vpiHandle reg(int reason, unsigned delay, const char *name) {
  s_vpi_time time = {.type = vpiSimTime, .low = delay};
  s_cb_data cb = {.reason = reason,
                  .cb_rtn = call,
                  .time = &time,
                  .user_data = (PLI_BYTE8 *)name};
  return vpi_register_cb(&cb);
}
static PLI_INT32 call(p_cb_data cb) {
  const char *name = (const char *)cb->user_data;
  if (cb->reason == cbEndOfCompile) {
    puts("end-compile");
    return 0;
  }
  if (cb->reason == cbStartOfSimulation) {
    puts("start");
    const char *stage = getenv("CLOCK_SYNC");
    if (stage) {
      variable = vpi_handle_by_name((PLI_BYTE8 *)"top.q", 0);
      assert(variable);
      assert(reg(!strcmp(stage, "nba") ? cbNBASynch : cbAtEndOfSimTime, 5, "at edge"));
      return 0;
    }
    variable = vpi_handle_by_name((PLI_BYTE8 *)"top.value", 0);
    assert(variable);
    if (vpi_handle_by_name((PLI_BYTE8 *)"top.idle", 0)) {
      assert(reg(cbAtEndOfSimTime, 3, "last-slot"));
      return 0;
    }
    assert(reg(cbNextSimTime, 99, "next"));
    assert(reg(cbAfterDelay, 2, "timer"));
    assert(reg(cbAtStartOfSimTime, 2, "begin"));
    cancelled = reg(cbAtStartOfSimTime, 2, "cancelled");
    assert(cancelled);
    assert(reg(cbReadOnlySynch, 2, "read-only"));
    assert(reg(cbAtEndOfSimTime, 2, "end-slot"));
    assert(reg(cbNBASynch, 2, "nba"));
    assert(reg(cbAtStartOfSimTime, 7, "otherwise-empty"));
    return 0;
  }
  if (cb->reason == cbEndOfSimulation) {
    puts("finish");
    return 0;
  }
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(variable, &v);
  if (!strcmp(name, "at edge")) {
    s_vpi_value clock = {.format = vpiIntVal};
    vpi_get_value(vpi_handle_by_name((PLI_BYTE8 *)"top.clk", 0), &clock);
    printf("at edge t=%u clk=%d q=%d\n", cb->time->low, clock.value.integer, v.value.integer);
    if (cb->time->low == 5)
      assert(reg(cb->reason, 10, "at edge"));
    return 0;
  }
  printf("%s t=%u value=%d\n", name, cb->time->low, v.value.integer);
  assert(strcmp(name, "phantom"));
  if (!strcmp(name, "last-slot")) {
    assert(reg(cbNextSimTime, 0, "phantom"));
  } else if (!strcmp(name, "begin")) {
    assert(vpi_remove_cb(cancelled));
    assert(reg(cbAtStartOfSimTime, 0, "nested-begin"));
  } else if (!strcmp(name, "timer")) {
    assert(!reg(cbAtStartOfSimTime, 0, "late-begin"));
  } else if (!strcmp(name, "next") && cb->time->low == 2) {
    assert(reg(cbNextSimTime, 0, "next"));
  } else if (!strcmp(name, "read-only")) {
    assert(!reg(cbReadWriteSynch, 0, "late-rw"));
    s_vpi_value update = {.format = vpiIntVal, .value.integer = 99};
    vpi_put_value(variable, &update, 0, vpiNoDelay);
    assert(vpi_chk_error(0));
    vpi_get_value(variable, &v);
    assert(v.value.integer == 3);
  }
  return 0;
}
static void start(void) {
  assert(reg(cbEndOfCompile, 0, "compile"));
  assert(reg(cbStartOfSimulation, 0, "start"));
  assert(reg(cbEndOfSimulation, 0, "end"));
}
void (*vlog_startup_routines[])(void) = {start, 0};

//--- idle.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  int value;
  bit idle;
  initial #3 value = 7;
endmodule
