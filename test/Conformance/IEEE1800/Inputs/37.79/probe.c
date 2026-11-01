#include "sv_vpi_user.h"
#include <stdio.h>

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type != vpiAssignStmt && type != vpiDeassign && type != vpiForce && type != vpiRelease)
      continue;
    vpiHandle lhs = vpi_handle(vpiLhs, s);
    printf("%s", vpi_get_str(vpiType, s));
    printf(" lhs=%s", lhs ? vpi_get_str(vpiName, lhs) : "null");
    if (type == vpiAssignStmt || type == vpiForce) {
      vpiHandle rhs = vpi_handle(vpiRhs, s);
      printf(" rhs=%s\n", rhs ? vpi_get_str(vpiName, rhs) : "null");
    } else
      printf(" rhs=none\n");
  }
}
