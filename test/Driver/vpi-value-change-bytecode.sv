// REQUIRES: native-elf
// RUN: %split-file %s %t
// RUN: %target_clang -fPIC -shared -nostdlib %t/plugin.c -I%resource_dir/include -o %t/plugin.so
// RUN: talos -O3 --vpi=full --execution-tier=bytecode %t/design.sv %t/plugin.so -o %t/full
// RUN: %t/full +puts | FileCheck %s --check-prefix=FULL
// RUN: talos -O3 --vpi=full %t/design.sv %t/plugin.so -o %t/native
// RUN: %t/native +uncertified | FileCheck %s --check-prefix=NATIVE

// LRM 4.10/38.36.1 and C6: repeated writes, same-value suppression, X/Z,
// stable event payloads, and no reentrant delivery inside callback/DPI puts.
// Native execution is explicitly declined until all writers are certified.
// FULL: change t=0 value=0/0
// FULL-NEXT: change t=1 value=1/0
// FULL-NEXT: issuer returned
// FULL-NEXT: change t=1 value=3/0
// FULL-NEXT: change t=1 value=4/0
// FULL-NEXT: change t=1 value=2/0
// FULL-NEXT: change t=2 value=ff/ff
// FULL-NEXT: change t=2 value=0/ff
// FULL-NEXT: foreign returned
// FULL-NEXT: change t=3 value=5/0
// FULL-NEXT: change t=3 value=6/0
// FULL-NEXT: SV after foreign
// FULL-NEXT: changes=9
// NATIVE: declined uncertified native writers
// NATIVE: changes=0

//--- design.sv
module top;
  import "DPI-C" context function void foreign_puts();
  logic [7:0] x;
  initial begin
    x = 0;
    #1;
    x = 1;
    x = 2;
    x = 2;
    #1;
    x = 'x;
    x = 'z;
    #1;
    if ($test$plusargs("puts")) begin
      foreign_puts();
      if (x !== 6) $fatal(1, "foreign writes not visible");
    end
    $display("SV after foreign");
    $finish;
  end
endmodule

//--- plugin.c
#include "sv_vpi_user.h"
#include "vpi_user.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static vpiHandle object;
static unsigned depth, putting, calls, can_write, uncertified;

static void put_pair(unsigned first) {
  s_vpi_value value = {0};
  value.format = vpiIntVal;
  putting = 1;
  value.value.integer = first;
  vpi_put_value(object, &value, 0, vpiNoDelay);
  value.value.integer = first + 1;
  vpi_put_value(object, &value, 0, vpiNoDelay);
  putting = 0;
}

void foreign_puts(void) {
  const unsigned before = calls;
  put_pair(5);
  assert(calls == before);
  puts("foreign returned");
}

static PLI_INT32 changed(p_cb_data data) {
  assert(!depth && !putting);
  ++depth;
  assert(data->reason == cbValueChange && data->obj && data->time && data->value);
  ++calls;
  printf("change t=%u value=%x/%x\n", data->time->low,
         data->value->value.vector[0].aval,
         data->value->value.vector[0].bval);
  if (can_write && !data->value->value.vector[0].bval &&
      data->value->value.vector[0].aval == 1) {
    const unsigned before = calls;
    put_pair(3);
    assert(calls == before);
    assert(data->value->value.vector[0].aval == 1);
    puts("issuer returned");
  }
  --depth;
  return 0;
}

static PLI_INT32 end(p_cb_data unused) {
  (void)unused;
  assert(calls == (uncertified ? 0u : can_write ? 9u : 5u));
  printf("changes=%u\n", calls);
  return 0;
}

static PLI_INT32 start(p_cb_data unused) {
  (void)unused;
  s_vpi_vlog_info info;
  assert(vpi_get_vlog_info(&info));
  for (int i = 0; i != info.argc; ++i) {
    can_write |= strcmp(info.argv[i], "+puts") == 0;
    uncertified |= strcmp(info.argv[i], "+uncertified") == 0;
  }
  object = vpi_handle_by_name((PLI_BYTE8 *)"top.x", 0);
  assert(object);
  s_vpi_time time = {vpiSimTime, 0, 0, 0};
  s_vpi_value value = {0};
  value.format = vpiVectorVal;
  s_cb_data callback = {cbValueChange, changed, 0, &time, &value, 0, 0};
  callback.obj = object;
  vpiHandle handle = vpi_register_cb(&callback);
  if (uncertified) {
    s_vpi_error_info error = {0};
    assert(!handle && vpi_chk_error(&error));
    assert(strstr(error.message, "certified writer path"));
    puts("declined uncertified native writers");
  } else {
    assert(handle);
  }
  return 0;
}

static void startup(void) {
  s_cb_data callback = {0};
  callback.reason = cbStartOfSimulation;
  callback.cb_rtn = start;
  assert(vpi_register_cb(&callback));
  callback.reason = cbEndOfSimulation;
  callback.cb_rtn = end;
  assert(vpi_register_cb(&callback));
}
void (*vlog_startup_routines[])(void) = {startup, 0};
