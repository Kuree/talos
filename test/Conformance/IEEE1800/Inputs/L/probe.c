#define VPI_COMPATIBILITY_VERSION_1800v2017 1
#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  vpiHandle n = vpi_handle_by_name("top.n", 0);
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(n, &v);
  vpiHandle it = vpi_iterate(vpiVariables, vpi_handle(vpiScope, n));
  printf("type=%d value=%d next=%d\n", vpi_get(vpiType, n) == vpiIntVar, v.value.integer, it && vpi_scan(it) != 0);
}
