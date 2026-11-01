#include "sv_vpi_user.h"
#include <stdio.h>
static vpiHandle signal;
static int now_low(void) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(0, &now);
  return now.low;
}
static int read_v(void) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(signal, &v);
  return v.value.integer;
}
static PLI_INT32 changed(p_cb_data data) {
  printf("value change t=%d v=%d\n", now_low(), read_v());
  return 0;
}
static PLI_INT32 later(p_cb_data data) {
  printf("after delay t=%d v=%d\n", now_low(), read_v());
  return 0;
}
static PLI_INT32 finished(p_cb_data data) {
  printf("end of simulation t=%d\n", now_low());
  return 0;
}
static PLI_INT32 compiled(p_cb_data data) {
  signal = vpi_handle_by_name("top.v", 0);
  s_vpi_time none = {.type = vpiSuppressTime}, delay = {.type = vpiSimTime, .low = 2};
  s_vpi_value value = {.format = vpiSuppressVal};
  s_cb_data change = {.reason = cbValueChange, .cb_rtn = changed, .obj = signal, .time = &none, .value = &value};
  s_cb_data timed = {.reason = cbAfterDelay, .cb_rtn = later, .time = &delay};
  vpi_register_cb(&change);
  vpi_register_cb(&timed);
  return 0;
}
static void start(void) {
  s_cb_data compile = {.reason = cbEndOfCompile, .cb_rtn = compiled};
  s_cb_data end = {.reason = cbEndOfSimulation, .cb_rtn = finished};
  vpi_register_cb(&compile);
  vpi_register_cb(&end);
}
void (*vlog_startup_routines[])(void) = {start, 0};
