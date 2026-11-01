#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
// 39.3.1 b): iterate all assertions in an instance.
static vpiHandle assertion(const char *name) {
  vpiHandle all = vpi_iterate(vpiAssertion, vpi_handle_by_name("top", 0));
  for (vpiHandle a; all && (a = vpi_scan(all));) {
    if (!strcmp(vpi_get_str(vpiName, a), name)) {
      vpi_release_handle(all);
      return a;
    }
  }
  return NULL;
}
void reset_flushed(void) {
  vpiHandle a = assertion("flushed");
  printf("flushed found=%d reset=%d\n", a != NULL, a ? vpi_control(vpiAssertionReset, a) : 0);
}
void disable_matured(void) {
  vpiHandle a = assertion("matured");
  printf("matured found=%d disable=%d\n", a != NULL, a ? vpi_control(vpiAssertionDisable, a) : 0);
}
