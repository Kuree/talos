// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -shared -fPIC -nostdlib -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: talos -O3 --vpi=read --mlir-timing +define+NATIVE_QUERY %t/top.sv %t/client.so -o %t/native 2>%t/plan && FileCheck %s --check-prefix=PLAN < %t/plan
// RUN: %t/native | FileCheck %s --check-prefix=IDLE && env WATCH_CLOCK=top.clk FULL_RUN=1 %t/native | FileCheck %s --check-prefix=FULL
// RUN: env WATCH_CLOCK=top.clk %t/native >%t/source && FileCheck %s --check-prefix=SOURCE < %t/source && env WATCH_CLOCK=top.cg.o %t/native >%t/primary && FileCheck %s --check-prefix=PRIMARY < %t/primary
// RUN: env WATCH_CLOCK=top.a.cp %t/native >%t/copy && FileCheck %s --check-prefix=COPY < %t/copy && env WATCH_CLOCK=top.a.cp DETACH=1 TALOS_RT_SIGNAL_DIAGNOSTICS=1 %t/native >%t/detach 2>&1 && FileCheck %s --check-prefix=DETACH < %t/detach
// RUN: talos -O0 --vpi=read --execution-tier=bytecode %t/top.sv %t/client.so -o %t/vm
// RUN: env WATCH_CLOCK=top.clk %t/vm | diff -u %t/source - && env WATCH_CLOCK=top.a.cp %t/vm | diff -u %t/copy - && env WATCH_CLOCK=top.cg.o %t/vm | diff -u %t/primary -
//
// The constant DPI export selects a shared native clock calendar. After
// two unobserved edges, start observing either end of a distinct variable
// port. Finishing at its publication preserves the intermediate state
// (1800-2023 4.9.1, 4.10, 38.36.1).
// PLAN: talos periodic forwarding: aliases=36
// All 69 time-zero copy activations remain admitted when their only return
// is the true edge of a VPI termination check.
// PLAN: talos started owners: admitted=102 time_zero=69
// PLAN: talos periodic alias byte run: bytes=
// FULL: end clk=0 cp=0 q=3 changes=6
// IDLE: end clk=0 cp=0 q=3 changes=0
// SOURCE: edge 15 clk=1 cp=0 q=1
// SOURCE-NEXT: end clk=1 cp=0 q=1 changes=1
// PRIMARY: edge 15 clk=0 cp=0 q=1
// PRIMARY-NEXT: end clk=0 cp=0 q=1 changes=1
// COPY: edge 15 clk=1 cp=1 q=1
// COPY-NEXT: end clk=1 cp=1 q=1 changes=1
// DETACH-DAG: talos-read-clock-views selected=36 candidates=36
// DETACH-DAG: end clk=0 cp=0 q=3 changes=2
// DETACH-DAG: aot_fallbacks=0
//--- top.sv
module leaf(input var bit cp);
  timeunit 1ns; timeprecision 1ns;
  bit [7:0] q;
  always @(posedge cp) q <= q + 1;
endmodule
module wire_copy(input wire i, output wire o);
  timeunit 1ns; timeprecision 1ns;
  assign o = i;
endmodule
module oscillator(output bit o);
  timeunit 1ns; timeprecision 1ns;
  always #5 o = !o;
endmodule
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  oscillator cg(clk);
  wire first, second;
  wire_copy f(clk, first);
  wire_copy g(first, second);
  leaf a(second);
  for (genvar i = 0; i < 32; ++i) begin : others
    wire forwarded;
    wire_copy fork_copy(second, forwarded);
    leaf extra(forwarded);
  end
`ifdef NATIVE_QUERY
  export "DPI-C" function constant_query;
  function int constant_query(); return 17; endfunction
`endif
  initial #32 $finish;
endmodule

//--- client.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static vpiHandle clk, cp, q, watch;
static int changes;
static int sample(vpiHandle obj) {
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(obj, &value);
  return value.value.integer;
}
static PLI_INT32 observe(p_cb_data data) {
  if (getenv("DETACH")) {
    assert(data->time->low == 15u + 5u * changes);
    assert(sample(cp) == (changes == 0));
    if (++changes == 2)
      assert(vpi_remove_cb(watch));
    return 0;
  }
  if (getenv("FULL_RUN")) {
    assert(data->time->low == 5u * (changes + 1));
    ++changes;
    return 0;
  }
  assert(data->time->low == 15);
  printf("edge %u clk=%d cp=%d q=%d\n", data->time->low, sample(clk),
         sample(cp), sample(q));
  ++changes;
  vpi_control(vpiFinish, 0);
  return 0;
}
static PLI_INT32 attach(p_cb_data data) {
  const char *name = getenv("WATCH_CLOCK");
  if (name) {
    s_vpi_time time = {.type = vpiSimTime};
    s_vpi_value value = {.format = vpiIntVal};
    s_cb_data cb = {.reason = cbValueChange,
                    .cb_rtn = observe,
                    .obj = vpi_handle_by_name((PLI_BYTE8 *)name, 0),
                    .time = &time,
                    .value = &value};
    assert(cb.obj);
    watch = vpi_register_cb(&cb);
    assert(watch);
  }
  return 0;
}
static PLI_INT32 start(p_cb_data data) {
  clk = vpi_handle_by_name((PLI_BYTE8 *)"top.clk", 0);
  cp = vpi_handle_by_name((PLI_BYTE8 *)"top.a.cp", 0);
  q = vpi_handle_by_name((PLI_BYTE8 *)"top.a.q", 0);
  assert(clk && cp && q);
  if (getenv("FULL_RUN"))
    return attach(data);
  s_vpi_time time = {.type = vpiSimTime, .low = 12};
  s_cb_data cb = {.reason = cbReadOnlySynch, .cb_rtn = attach, .time = &time};
  assert(vpi_register_cb(&cb));
  return 0;
}
static PLI_INT32 finish(p_cb_data data) {
  printf("end clk=%d cp=%d q=%d changes=%d\n", sample(clk), sample(cp),
         sample(q), changes);
  return 0;
}
static void init(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = finish;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {init, 0};
