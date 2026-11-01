#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static vpiHandle local;
static int now(void) {
  s_vpi_time t = {.type = vpiSimTime};
  vpi_get_time(0, &t);
  return t.low;
}
static PLI_INT32 created(p_cb_data data) {
  printf("created class %s t=%d\n", vpi_get_str(vpiName, data->obj), now());
  return 0;
}
static PLI_INT32 frame_end(p_cb_data data) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(local, &v);
  printf("frame ended a=%d t=%d\n", v.value.integer, now());
  return 0;
}
static PLI_INT32 thread_end(p_cb_data data) {
  printf("thread ended t=%d\n", now());
  return 0;
}
static vpiHandle track(PLI_INT32 reason, vpiHandle obj, PLI_INT32 (*routine)(p_cb_data)) {
  s_vpi_time time = {.type = vpiSimTime};
  s_vpi_value value = {.format = vpiSuppressVal};
  s_cb_data cb = {.reason = reason, .cb_rtn = routine, .obj = obj, .time = &time, .value = &value};
  return vpi_register_cb(&cb);
}
void track_class(void) {
  vpiHandle type = vpi_handle(vpiClassTypespec, vpi_handle_by_name("top.c", 0));
  printf("registered create=%d\n", track(cbCreateObj, type, created) != 0);
}
void track_frame(void) {
  vpiHandle frame = vpi_handle(vpiFrame, 0);
  for (; frame && !local; frame = local ? frame : vpi_handle(vpiParent, frame)) {
    vpiHandle it = vpi_iterate(vpiAutomatics, frame);
    for (vpiHandle h; it && (h = vpi_scan(it));)
      if (!strcmp(vpi_get_str(vpiName, h), "a"))
        local = h;
  }
  printf("registered frame=%d\n", frame && track(cbEndOfFrame, frame, frame_end) != 0);
}
void track_thread(void) {
  vpiHandle thread = vpi_handle(vpiThread, 0);
  printf("registered thread=%d\n", thread && track(cbEndOfThread, thread, thread_end) != 0);
}
