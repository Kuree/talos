#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 bump(PLI_BYTE8 *data) {
  vpiHandle arg = vpi_scan(vpi_iterate(vpiArgument, vpi_handle(vpiSysTfCall, 0)));
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(arg, &v);
  v.value.integer++;
  vpi_put_value(arg, &v, 0, vpiNoDelay);
  return 0;
}
static PLI_INT32 sized(PLI_BYTE8 *data) {
  s_vpi_value v = {.format = vpiIntVal};
  v.value.integer = 165;
  vpi_put_value(vpi_handle(vpiSysTfCall, 0), &v, 0, vpiNoDelay);
  return 0;
}
static PLI_INT32 width(PLI_BYTE8 *data) { return 8; }
static void start(void) {
  s_vpi_systf_data task = {.type = vpiSysTask, .tfname = "$bump", .calltf = bump};
  s_vpi_systf_data function = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$sized", .calltf = sized, .sizetf = width};
  vpi_register_systf(&task);
  vpi_register_systf(&function);
}
void (*vlog_startup_routines[])(void) = {start, 0};
