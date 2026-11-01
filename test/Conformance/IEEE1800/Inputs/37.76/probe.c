#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void side(const char *label, vpiHandle e) {
  printf(" %s=%s", label, e ? vpi_get_str(vpiName, e) : "null");
  printf("=%d", e ? value(e) : -1);
}

void probe(void) {
  vpiHandle it = vpi_iterate(vpiAliasStmt, vpi_handle_by_name("top", 0)), s;
  int count = 0;
  while (it && (s = vpi_scan(it))) {
    ++count;
    printf("%s", vpi_get_str(vpiType, s));
    side("lhs", vpi_handle(vpiLhs, s));
    side("rhs", vpi_handle(vpiRhs, s));
    printf("\n");
  }
  printf("aliases=%d\n", count);
}
