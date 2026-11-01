#include "sv_vpi_user.h"
#include <stdio.h>
static int compiles, calls;
static PLI_INT32 compile_check(PLI_BYTE8 *data) {
  compiles++;
  return 0;
}
static PLI_INT32 call(PLI_BYTE8 *data) {
  calls++;
  return 0;
}
static PLI_INT32 report(p_cb_data data) {
  printf("%s simulation compiletf=%d calltf=%d\n", data->user_data, compiles, calls);
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$checked", .compiletf = compile_check, .calltf = call};
  s_cb_data before = {.reason = cbStartOfSimulation, .cb_rtn = report, .user_data = "before"};
  s_cb_data after = {.reason = cbEndOfSimulation, .cb_rtn = report, .user_data = "after"};
  vpi_register_systf(&t);
  vpi_register_cb(&before);
  vpi_register_cb(&after);
}
void (*vlog_startup_routines[])(void) = {start, 0};
