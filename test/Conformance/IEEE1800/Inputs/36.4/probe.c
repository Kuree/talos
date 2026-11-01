#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 get_vector(PLI_BYTE8 *data) {
  vpiHandle it = vpi_iterate(vpiArgument, vpi_handle(vpiSysTfCall, 0));
  vpiHandle file = vpi_scan(it), bus = vpi_scan(it);
  printf("args=%d\n", (file != 0) + (bus != 0));
  s_vpi_value v = {.format = vpiStringVal};
  vpi_get_value(file, &v);
  printf("file=%s\n", v.value.str);
  v.format = vpiIntVal;
  vpi_get_value(bus, &v);
  printf("input_bus was %d\n", v.value.integer);
  v.value.integer = 200;
  vpi_put_value(bus, &v, 0, vpiNoDelay);
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$get_vector", .calltf = get_vector};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
