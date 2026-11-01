#include "sv_vpi_user.h"
#include <stdio.h>

static PLI_INT32 fired(p_cb_data data) {
  if (data->reason == cbValueChange)
    printf("fired %s value=%d\n", data->user_data, data->value->value.integer);
  else
    printf("fired %s\n", data->user_data);
  return 0;
}

static const char *reason_name(int reason) {
  return reason == cbValueChange ? "cbValueChange" : reason == cbEndOfSimulation ? "cbEndOfSimulation" : "other";
}

static void list(const char *where, vpiHandle object) {
  vpiHandle it = vpi_iterate(vpiCallback, object), cb;
  int count = 0;
  while (it && (cb = vpi_scan(it))) {
    s_vpi_time time = {.type = vpiSimTime};
    s_vpi_value val = {.format = vpiIntVal};
    s_cb_data info = {.time = &time, .value = &val};
    vpi_get_cb_info(cb, &info);
    ++count;
    printf("%s: %s", where, vpi_get_str(vpiType, cb));
    printf(" reason=%s", reason_name(info.reason));
    printf(" obj=%s", info.obj ? vpi_get_str(vpiName, info.obj) : "null");
    printf(" user=%s\n", info.user_data ? info.user_data : "null");
  }
  printf("%s: count=%d\n", where, count);
}

void probe(void) {
  vpiHandle v = vpi_handle_by_name("top.v", 0);
  s_vpi_time time = {.type = vpiSuppressTime};
  s_vpi_value val = {.format = vpiIntVal};
  s_cb_data change = {.reason = cbValueChange, .cb_rtn = fired, .obj = v, .time = &time, .value = &val, .user_data = "watch-v"};
  s_cb_data end = {.reason = cbEndOfSimulation, .cb_rtn = fired, .user_data = "at-end"};
  vpi_register_cb(&change);
  vpi_register_cb(&end);
  list("on v", v);
  list("on NULL", NULL);
}
