#include "sv_vpi_user.h"
#include <stdio.h>
static int read_n(void) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(vpi_handle_by_name("top.n", 0), &v);
  return v.value.integer;
}
static PLI_INT32 later(p_cb_data data) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(0, &now);
  printf("t=%d n=%d\n", now.low, read_n());
  return 0;
}
static PLI_INT32 finished(p_cb_data data) {
  printf("end n=%d\n", read_n());
  return 0;
}
static PLI_INT32 started(p_cb_data data) {
  s_vpi_time delay = {.type = vpiSimTime, .low = 2};
  s_cb_data cb = {.reason = cbAfterDelay, .cb_rtn = later, .time = &delay};
  vpi_register_cb(&cb);
  return 0;
}
static void start(void) {
  s_cb_data on_start = {.reason = cbStartOfSimulation, .cb_rtn = started};
  s_cb_data on_end = {.reason = cbEndOfSimulation, .cb_rtn = finished};
  vpi_register_cb(&on_start);
  vpi_register_cb(&on_end);
}
void (*vlog_startup_routines[])(void) = {start, 0};
