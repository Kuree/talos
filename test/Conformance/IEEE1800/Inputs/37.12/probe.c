#include "sv_vpi_user.h"
#include <stdio.h>
static int count(int relation, vpiHandle h) {
  int n = 0;
  vpiHandle it = vpi_iterate(relation, h);
  while (it && vpi_scan(it))
    n++;
  return n;
}
void probe(void) {
  vpiHandle top = vpi_handle_by_name("top", 0);
  int unnamed = 0;
  vpiHandle it = vpi_iterate(vpiInternalScope, top);
  for (vpiHandle s; it && (s = vpi_scan(it));) {
    int type = vpi_get(vpiType, s);
    printf("scope type=%s", vpi_get_str(vpiType, s));
    if (type == vpiBegin) {
      unnamed++;
      printf(" vars=%d", count(vpiVariables, s));
    } else {
      printf(" name=%s", vpi_get_str(vpiName, s));
      printf(" full=%s", vpi_get_str(vpiFullName, s));
    }
    printf(" up=%s", vpi_get_str(vpiFullName, vpi_handle(vpiScope, s)));
    if (type == vpiNamedFork)
      printf(" join-any=%d", vpi_get(vpiJoinType, s) == vpiJoinAny);
    printf("\n");
  }
  printf("unnamed begin scopes=%d\n", unnamed);
  vpiHandle blk = vpi_handle_by_name("top.blk", 0);
  vpiHandle inner = blk ? vpi_scan(vpi_iterate(vpiInternalScope, blk)) : 0;
  if (!inner) {
    printf("nested null\n");
    return;
  }
  vpiHandle v = vpi_scan(vpi_iterate(vpiVariables, inner));
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(v, &value);
  printf("nested full=%s", vpi_get_str(vpiFullName, inner));
  printf(" var=%s value=%d\n", vpi_get_str(vpiFullName, v), value.value.integer);
}
