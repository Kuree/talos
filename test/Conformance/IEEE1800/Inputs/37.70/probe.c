#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

void probe(void) {
  vpiHandle it = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  while ((p = vpi_scan(it))) {
    vpiHandle s = vpi_handle(vpiStmt, p);
    if (!s || vpi_get(vpiType, s) != vpiForever)
      continue;
    vpiHandle body = vpi_handle(vpiStmt, s);
    vpiHandle inner = body ? vpi_handle(vpiStmt, body) : NULL;
    vpiHandle lhs = inner ? vpi_handle(vpiLhs, inner) : NULL;
    printf("%s", vpi_get_str(vpiType, s));
    printf(" body=%s", body ? vpi_get_str(vpiType, body) : "null");
    printf(" inner=%s", inner ? vpi_get_str(vpiType, inner) : "null");
    printf(" lhs=%s", lhs ? vpi_get_str(vpiName, lhs) : "null");
    printf("=%d\n", lhs ? value(lhs) : -1);
  }
}
