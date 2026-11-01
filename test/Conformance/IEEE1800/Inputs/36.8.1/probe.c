#include "sv_vpi_user.h"
#include <stdio.h>
static int sized_calls, real_calls;
static PLI_INT32 width(PLI_BYTE8 *data) {
  ++*(int *)data;
  return 8;
}
static PLI_INT32 give(PLI_BYTE8 *data) {
  s_vpi_value v = {.format = vpiIntVal};
  v.value.integer = 165;
  vpi_put_value(vpi_handle(vpiSysTfCall, 0), &v, 0, vpiNoDelay);
  return 0;
}
static PLI_INT32 give_real(PLI_BYTE8 *data) {
  s_vpi_value v = {.format = vpiRealVal};
  v.value.real = 1.5;
  vpi_put_value(vpi_handle(vpiSysTfCall, 0), &v, 0, vpiNoDelay);
  return 0;
}
static PLI_INT32 report(p_cb_data data) {
  printf("sizetf sized=%d real=%d\n", sized_calls, real_calls);
  return 0;
}
static void start(void) {
  s_vpi_systf_data sized = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$sized", .calltf = give, .sizetf = width, .user_data = (PLI_BYTE8 *)&sized_calls};
  s_vpi_systf_data plain = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$plain", .calltf = give};
  s_vpi_systf_data realf = {.type = vpiSysFunc, .sysfunctype = vpiRealFunc, .tfname = "$realf", .calltf = give_real, .sizetf = width, .user_data = (PLI_BYTE8 *)&real_calls};
  s_cb_data end = {.reason = cbEndOfSimulation, .cb_rtn = report};
  vpi_register_systf(&sized);
  vpi_register_systf(&plain);
  vpi_register_systf(&realf);
  vpi_register_cb(&end);
}
void (*vlog_startup_routines[])(void) = {start, 0};
