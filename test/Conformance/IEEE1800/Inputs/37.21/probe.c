#include "sv_vpi_user.h"
#include <stdio.h>
static int walk(int relation, vpiHandle v, vpiHandle *last) {
  int n = 0;
  vpiHandle it = vpi_iterate(relation, v);
  for (vpiHandle h; it && (h = vpi_scan(it)); n++)
    if (last)
      *last = h;
  return n;
}
static void show(const char *plural, const char *single, int relation, vpiHandle v) {
  vpiHandle one = 0;
  int n = walk(relation, v, &one);
  printf("%s=%d", plural, n);
  if (one && vpi_get(vpiType, one) == vpiContAssign) {
    s_vpi_value value = {.format = vpiIntVal};
    vpi_get_value(vpi_handle(vpiRhs, one), &value);
    printf(" %s type=%s", single, vpi_get_str(vpiType, one));
    printf(" lhs=%s rhs=%d", vpi_get_str(vpiFullName, vpi_handle(vpiLhs, one)), value.value.integer);
  }
  printf("\n");
}
void probe(void) {
  vpiHandle v = vpi_handle_by_name("top.v", 0);
  show("drivers", "driver", vpiDriver, v);
  show("loads", "load", vpiLoad, v);
  printf("undriven drivers=%d unread loads=%d\n", walk(vpiDriver, vpi_handle_by_name("top.a", 0), 0),
         walk(vpiLoad, vpi_handle_by_name("top.l", 0), 0));
}
