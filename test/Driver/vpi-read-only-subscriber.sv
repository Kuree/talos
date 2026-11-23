// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -nostdlib -shared -fPIC -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: talos -O3 --vpi=read %t/top.sv %t/client.so -o %t/native && env TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/native > %t/out 2> %t/diag && FileCheck %s < %t/out && FileCheck %s --check-prefix=FRAME < %t/diag
// RUN: talos -O0 --execution-tier=bytecode --vpi=read %t/top.sv %t/client.so -o %t/bc && %t/bc | diff -u %t/out -
// Postponed samples include the current slot's NBA and the last value of a
// private procedural temporary. A callback can rearm for a slot with no clock.
// The subscribed port's implicit assignment materializes its native frame
// on demand. It publishes all ten updates in the same order as bytecode.
// FRAME: talos-started-owners {{.*}}virtual_materializations={{[1-9][0-9]*}}
// CHECK: sample 4 q=0
// CHECK-NEXT: sample 5 q=1
// CHECK-NEXT: sample 6 q=1
// CHECK-NEXT: sample 15 q=2
// CHECK-NEXT: sample 25 q=3
// CHECK-NEXT: final=10

//--- top.sv
module port_view(input var bit [7:0] source, output var bit [7:0] sink);
  timeunit 1ns; timeprecision 1ns;
  assign sink = source;
endmodule
module top;
 timeunit 1ns; timeprecision 1ns;
 bit clk;
 bit [7:0] q, mirror;
 port_view view(q, mirror);
 always #5 clk = !clk;
 always_ff @(posedge clk) begin : counter
   static bit [7:0] next_count;
   next_count = q + 1;
   q <= next_count;
 end
 initial begin #100; $finish; end
endmodule

//--- client.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
static unsigned count;
static vpiHandle q, local;
static const unsigned ts[] = {4, 5, 6, 15, 25};
static int read_int(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static PLI_INT32 sample(p_cb_data cb);
static void arm(unsigned delta) {
  s_vpi_time time = {.type = vpiSimTime, .low = delta};
  s_cb_data cb = {.reason = cbReadOnlySynch, .cb_rtn = sample, .time = &time};
  assert(vpi_register_cb(&cb));
}
static PLI_INT32 sample(p_cb_data cb) {
  assert(cb->time->low == ts[count]);
  int value = read_int(q);
  assert(read_int(local) == value);
  printf("sample %u q=%d\n", ts[count], value);
  if (++count < sizeof(ts) / sizeof(ts[0]))
    arm(ts[count] - ts[count - 1]);
  return 0;
}
static unsigned port_changes;
static PLI_INT32 port_change(p_cb_data cb) {
  assert(cb->value->value.integer == (int)++port_changes);
  return 0;
}
static PLI_INT32 start(p_cb_data cb) {
  q = vpi_handle_by_name((PLI_BYTE8 *)"top.q", 0);
  local = vpi_handle_by_name((PLI_BYTE8 *)"top.counter.next_count", 0);
  assert(q && local);
  s_vpi_time time = {.type = vpiSimTime};
  s_vpi_value value = {.format = vpiIntVal};
  s_cb_data watch = {.reason = cbValueChange, .cb_rtn = port_change,
                     .obj = vpi_handle_by_name((PLI_BYTE8 *)"top.view.sink", 0),
                     .time = &time, .value = &value};
  assert(watch.obj && vpi_register_cb(&watch));
  arm(ts[0]);
  return 0;
}
static PLI_INT32 end(p_cb_data cb) {
  assert(count == 5 && port_changes == 10);
  printf("final=%d\n", read_int(q));
  return 0;
}
static void startup(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = end;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {startup, 0};
