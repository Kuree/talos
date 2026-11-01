#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static PLI_INT32 before(p_cb_data cb) {
  s_vpi_value x = {.format = vpiIntVal};
  vpi_get_value(vpi_handle_by_name("top.x", 0), &x);
  printf("%s reason=%d rtn=%d", cb->user_data, cb->reason == cbStmt, cb->cb_rtn == before);
  printf(" obj=%s", vpi_get_str(vpiFullName, cb->obj));
  if (cb->time)
    printf(" time=%u", cb->time->low);
  else
    printf(" time=none");
  printf(" value=%s index=%d x=%d\n", cb->value ? "set" : "null", cb->index, x.value.integer);
  return 0;
}
static vpiHandle block(const char *name) {
  vpiHandle process = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle statements = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, process));
  for (vpiHandle s; statements && (s = vpi_scan(statements));) {
    if (vpi_get(vpiType, s) == vpiNamedBegin && !strcmp(vpi_get_str(vpiName, s), name)) {
      vpi_release_handle(statements);
      return s;
    }
  }
  return NULL;
}
void setup(void) {
  s_vpi_time simulation = {.type = vpiSimTime}, suppress = {.type = vpiSuppressTime};
  vpiHandle first = block("first"), second = block("second");
  printf("statements=%s", first ? vpi_get_str(vpiType, first) : "null");
  printf(",%s\n", second ? vpi_get_str(vpiType, second) : "null");
  s_cb_data cb = {.reason = cbStmt, .cb_rtn = before, .obj = first, .time = &simulation, .user_data = "twice"};
  // "Multiple calls to vpi_register_cb() with the same data shall result in multiple callbacks."
  int registered = vpi_register_cb(&cb) != 0;
  registered += vpi_register_cb(&cb) != 0;
  cb.obj = second;
  cb.time = &suppress;
  cb.user_data = "suppressed";
  registered += vpi_register_cb(&cb) != 0;
  printf("registered=%d\n", registered);
}
