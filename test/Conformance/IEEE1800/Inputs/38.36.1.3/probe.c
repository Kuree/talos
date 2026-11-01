#include "sv_vpi_user.h"
#include <stdio.h>
static vpiHandle handle;
static int count;
static PLI_INT32 before(p_cb_data cb) {
  s_vpi_value x = {.format = vpiIntVal};
  vpi_get_value(vpi_handle_by_name("top.u.x", 0), &x);
  count++;
  printf("%s", vpi_get_str(vpiType, cb->obj));
  printf(" scope=%s x=%d\n", vpi_get_str(vpiFullName, vpi_handle(vpiScope, cb->obj)), x.value.integer);
  return 0;
}
void setup(void) {
  s_vpi_time suppress = {.type = vpiSuppressTime};
  s_cb_data cb = {.reason = cbStmt, .cb_rtn = before, .obj = vpi_handle_by_name("top.u", 0), .time = &suppress};
  handle = vpi_register_cb(&cb);
  printf("handle=%s\n", handle ? vpi_get_str(vpiType, handle) : "null");
}
void drop(void) { printf("removed=%d\n", vpi_remove_cb(handle)); }
int firings(void) { return count; }
