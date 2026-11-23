// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -O2 -fPIC -shared -nostdlib -I%resource_dir/include %t/reader.c -o %t/reader.so
// RUN: talos -O3 --vpi=read %t/top.sv %t/reader.so -o %t/native && %t/native | FileCheck %s
// RUN: talos -O0 --vpi=read --execution-tier=bytecode %t/top.sv %t/reader.so -o %t/vm && %t/vm | FileCheck %s
// RUN: talos -O0 --execution-tier=bytecode --vpi=full %t/top.sv %t/reader.so -o %t/full && %t/full | FileCheck %s
// IEEE 1800-2023 38.4, 38.36.1, 9.2.3. The first publication ends the
// application on return from its callback. The rest of the source function,
// its caller, and another registration for the same change cannot run. Final
// procedures execute normally after the scheduler consumes that request.
// CHECK: first q=17
// CHECK-NEXT: final q=17 marker=0
// CHECK-NEXT: end q=17 marker=42 callbacks=1

//--- top.sv
module top;
  bit [31:0] q, marker;
  function automatic int update();
    q[7:0] = 8'h11;
    q[15:8] = 8'h22;
    marker = 10;
    return 11;
  endfunction
  initial begin
    #1 marker = update();
    $fatal(1, "executed caller after vpiFinish");
  end
  final begin
    $display("final q=%0d marker=%0d", q, marker);
    marker = 42;
  end
endmodule

//--- reader.c
#include "sv_vpi_user.h"
#include <assert.h>
#include <stdio.h>
static vpiHandle q, marker;
static unsigned callbacks;
static int read_int(vpiHandle handle) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(handle, &v);
  return v.value.integer;
}
static PLI_INT32 change(p_cb_data data) {
  ++callbacks;
  printf("first q=%d\n", data->value->value.integer);
  assert(vpi_control(vpiFinish, 0));
  return 0;
}
static PLI_INT32 start(p_cb_data data) {
  q = vpi_handle_by_name((PLI_BYTE8 *)"top.q", 0);
  marker = vpi_handle_by_name((PLI_BYTE8 *)"top.marker", 0);
  assert(q && marker);
  s_vpi_time t = {.type = vpiSimTime};
  s_vpi_value v = {.format = vpiIntVal};
  s_cb_data c = {.reason = cbValueChange, .cb_rtn = change,
                 .obj = q, .time = &t, .value = &v};
  assert(vpi_register_cb(&c));
  assert(vpi_register_cb(&c));
  return 0;
}
static PLI_INT32 finish(p_cb_data data) {
  printf("end q=%d marker=%d callbacks=%u\n", read_int(q), read_int(marker),
         callbacks);
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
