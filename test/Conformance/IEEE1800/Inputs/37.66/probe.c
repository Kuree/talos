#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void show(vpiHandle s) {
  vpiHandle c = vpi_handle(vpiCondition, s), body = vpi_handle(vpiStmt, s);
  printf("%s", vpi_get_str(vpiType, s));
  if (c && vpi_get(vpiType, c) == vpiOperation)
    printf(" condition=%s", vpi_get(vpiOpType, c) == vpiLtOp ? "vpiLtOp" : "other");
  else
    printf(" condition=%s", c ? vpi_get_str(vpiType, c) : "null");
  if (c)
    printf(" value=%d", value(c));
  printf(" body=%s", body ? vpi_get_str(vpiType, body) : "null");
  if (body) {
    vpiHandle lhs = vpi_handle(vpiLhs, body);
    printf(" lhs=%s", lhs ? vpi_get_str(vpiName, lhs) : "null");
    if (lhs)
      printf("=%d", value(lhs));
  }
  printf("\n");
}

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it)))
    if (vpi_get(vpiType, s) == vpiWhile || vpi_get(vpiType, s) == vpiRepeat)
      show(s);
}
