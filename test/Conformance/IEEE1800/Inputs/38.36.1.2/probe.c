#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 before(p_cb_data cb) {
  s_vpi_value x = {.format = vpiIntVal};
  vpi_get_value(vpi_handle_by_name("top.x", 0), &x);
  printf("%s t=%u x=%d\n", vpi_get_str(vpiType, cb->obj), cb->time->low, x.value.integer);
  return 0;
}
void setup(void) {
  s_vpi_time simulation = {.type = vpiSimTime};
  // The named block "body" is the first process's only vpiNamedBegin.
  vpiHandle process = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle outer = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, process)), body = NULL;
  for (vpiHandle s; outer && (s = vpi_scan(outer));)
    if (vpi_get(vpiType, s) == vpiNamedBegin)
      body = s;
  int found = 0, registered = 0;
  vpiHandle statements = body ? vpi_iterate(vpiStmt, body) : NULL;
  for (vpiHandle s; statements && (s = vpi_scan(statements)); found++) {
    s_cb_data cb = {.reason = cbStmt, .cb_rtn = before, .obj = s, .time = &simulation};
    registered += vpi_register_cb(&cb) != 0;
  }
  printf("statements=%d registered=%d\n", found, registered);
}
