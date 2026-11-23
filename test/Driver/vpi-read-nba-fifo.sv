// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -nostdlib -shared -fPIC -I%resource_dir/include %t/client.c -o %t/client.so
// RUN: talos -O3 --vpi=read --mlir-timing %t/top.sv %t/client.so -o %t/sim 2>%t/plan && FileCheck %s --check-prefix=PLAN < %t/plan
// RUN: %t/sim | FileCheck %s && env WATCH=1 %t/sim | FileCheck %s --check-prefix=WATCH
// RUN: talos -O3 --vpi=read --execution-tier=bytecode %t/top.sv %t/client.so -o %t/bc && env WATCH=1 %t/bc | FileCheck %s --check-prefix=WATCH
// RUN: talos -O3 --vpi=read %S/native-copy-activation.sv %t/client.so -o %t/force && %t/force | FileCheck %S/native-copy-activation.sv
// RUN: talos -O3 --vpi=read --execution-tier=bytecode %S/native-copy-activation.sv %t/client.so -o %t/force-bc && %t/force-bc | FileCheck %S/native-copy-activation.sv
// PLAN: talos native unchanged NBA roots: {{.*}}exclusive-fifo={{[1-9][0-9]*}}
// CHECK: pulses=5 q=00 neighbor=72
// CHECK: changes=0
// WATCH: pulses=5 q=00 neighbor=72
// WATCH: changes=20
//--- top.sv
module top;
  timeunit 1ns; timeprecision 1ns;
  bit clk;
  logic [7:0] q, neighbor;
  bit [7:0] pulses;
  always #5 clk = !clk;
  always @(posedge clk) begin
    neighbor <= 8'h72;
    q <= 8'h01;
    q <= 8'h00;
    q <= 8'hx0;
    q <= 8'h00;
  end
  always @(posedge q[0]) pulses++;
  initial begin
    #46;
    if (q !== 0 || pulses != 5 || neighbor !== 8'h72) $fatal;
    $display("pulses=%0d q=%h neighbor=%h", pulses, q, neighbor);
    $finish;
  end
endmodule
//--- client.c
#include "vpi_user.h"
#include <assert.h>
#include <stdlib.h>
static int changes;
static PLI_INT32 changed(p_cb_data cb) {
  s_vpi_vecval v = cb->value->value.vector[0];
  unsigned phase = changes++ % 4;
  assert((v.bval & 255) == (phase == 2 ? 240 : 0));
  assert((v.aval & ~v.bval & 255) == (phase == 0));
  return 0;
}
static PLI_INT32 start(p_cb_data unused) {
  if (getenv("WATCH")) {
    s_vpi_time t = {.type = vpiSimTime};
    s_vpi_value v = {.format = vpiVectorVal};
    s_cb_data cb = {.reason = cbValueChange, .cb_rtn = changed,
                    .obj = vpi_handle_by_name((PLI_BYTE8 *)"top.q", 0),
                    .time = &t, .value = &v};
    assert(cb.obj && vpi_register_cb(&cb));
  }
  return 0;
}
static PLI_INT32 done(p_cb_data unused) {
  vpi_printf("changes=%d\n", changes);
  return 0;
}
static void boot(void) {
  s_cb_data cb = {.reason = cbStartOfSimulation, .cb_rtn = start};
  assert(vpi_register_cb(&cb));
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = done;
  assert(vpi_register_cb(&cb));
}
void (*vlog_startup_routines[])(void) = {boot, 0};
