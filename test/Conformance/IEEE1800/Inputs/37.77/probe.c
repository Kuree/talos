#include "sv_vpi_user.h"
#include <stdio.h>

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type == vpiDisable) {
      vpiHandle target = vpi_handle(vpiExpr, s);
      printf("%s target=", vpi_get_str(vpiType, s));
      if (target) {
        printf("%s", vpi_get_str(vpiType, target));
        printf(":%s\n", vpi_get_str(vpiName, target));
      } else
        printf("null\n");
    } else if (type == vpiDisableFork) {
      printf("%s", vpi_get_str(vpiType, s));
      printf(" target=%s\n", vpi_handle(vpiExpr, s) ? "some" : "none");
    }
  }
}
