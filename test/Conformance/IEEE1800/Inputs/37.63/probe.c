#include "sv_vpi_user.h"
#include <stdio.h>

static const char *always_type(vpiHandle p) {
  if (vpi_get(vpiType, p) != vpiAlways)
    return "none";
  switch (vpi_get(vpiAlwaysType, p)) {
  case vpiAlways: return "vpiAlways";
  case vpiAlwaysComb: return "vpiAlwaysComb";
  case vpiAlwaysFF: return "vpiAlwaysFF";
  case vpiAlwaysLatch: return "vpiAlwaysLatch";
  }
  return "other";
}

void probe(void) {
  vpiHandle it = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  int count = 0;
  while ((p = vpi_scan(it))) {
    vpiHandle stmt = vpi_handle(vpiStmt, p), module = vpi_handle(vpiModule, p);
    ++count;
    printf("%s always=%s", vpi_get_str(vpiType, p), always_type(p));
    printf(" stmt=%s", stmt ? vpi_get_str(vpiType, stmt) : "null");
    printf(" module=%s\n", module ? vpi_get_str(vpiName, module) : "null");
  }
  printf("processes=%d\n", count);
}
