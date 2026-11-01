#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 hello(PLI_BYTE8 *data) {
  puts("hello from task");
  return 0;
}
static PLI_INT32 answer(PLI_BYTE8 *data) {
  s_vpi_value v = {.format = vpiIntVal};
  v.value.integer = 42;
  vpi_put_value(vpi_handle(vpiSysTfCall, 0), &v, 0, vpiNoDelay);
  return 0;
}
static void start(void) {
  s_vpi_systf_data task = {.type = vpiSysTask, .tfname = "$hello", .calltf = hello};
  s_vpi_systf_data function = {.type = vpiSysFunc, .sysfunctype = vpiIntFunc, .tfname = "$answer", .calltf = answer};
  int a = vpi_register_systf(&task) != 0, b = vpi_register_systf(&function) != 0;
  printf("registered task=%d function=%d\n", a, b);
}
void (*vlog_startup_routines[])(void) = {start, 0};
