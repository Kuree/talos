#include "sv_vpi_user.h"
#include <stdio.h>

/* The h.x reached from the statement h.x = 5, the second assignment of the block. */
static vpiHandle access_of_x(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p));
  vpi_scan(it);
  return vpi_handle(vpiLhs, vpi_scan(it));
}

void probe(const char *when) {
  vpiHandle lhs = access_of_x();
  if (!lhs) {
    printf("%s: lhs=null\n", when);
    return;
  }
  printf("%s: lhs=%s", when, vpi_get_str(vpiType, lhs));
  vpiHandle prefix = vpi_handle(vpiPrefix, lhs);
  int actual = vpi_get(vpiHasActual, lhs);
  if (actual == 1) {
    s_vpi_value v = {.format = vpiIntVal};
    vpi_get_value(lhs, &v);
    printf(" value=%d", v.value.integer);
  }
  if (prefix) {
    printf(" prefix=%s", vpi_get_str(vpiType, prefix));
    printf(":%s", vpi_get_str(vpiName, prefix));
  } else
    printf(" prefix=null");
  printf(" actual=%d\n", actual);
}
