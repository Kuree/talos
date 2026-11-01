#include "sv_vpi_user.h"
#include <stdio.h>

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  int count = 0, labels = 0;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    ++count;
    printf("%s", vpi_get_str(vpiType, s));
    /* A call's vpiName is its callee's (37.42), not a label. */
    if (type != vpiFuncCall && type != vpiSysTaskCall) {
      char *name = vpi_get_str(vpiName, s);
      printf(" label=%s", name ? name : "null");
      labels += name != NULL;
    }
    if (type == vpiNamedBegin || type == vpiForever || type == vpiRepeat) {
      vpiHandle it2 = vpi_iterate(vpiStmt, s), body = it2 ? vpi_scan(it2) : vpi_handle(vpiStmt, s);
      printf(" body=%s", body ? vpi_get_str(vpiType, body) : "null");
    }
    printf("\n");
  }
  printf("labels=%d statements=%d\n", labels, count);
}
