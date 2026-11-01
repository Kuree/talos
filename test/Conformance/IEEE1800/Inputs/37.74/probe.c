#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void targets(const char *label, int relation, vpiHandle loop) {
  vpiHandle it = vpi_iterate(relation, loop), s;
  printf(" %s=", label);
  while (it && (s = vpi_scan(it)))
    printf("%s,", vpi_get_str(vpiName, vpi_handle(vpiLhs, s)));
}

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    if (vpi_get(vpiType, s) != vpiFor)
      continue;
    int local = vpi_get(vpiLocalVarDecls, s);
    vpiHandle c = vpi_handle(vpiCondition, s), body = vpi_handle(vpiStmt, s);
    vpiHandle lhs = body ? vpi_handle(vpiLhs, body) : NULL;
    printf("%s local=%d", vpi_get_str(vpiType, s), local);
    printf(" condition=%s", !c ? "null" : vpi_get(vpiOpType, c) == vpiLtOp ? "vpiLtOp" : "other");
    if (!local) {
      /* The condition's variable is module storage here; a declared loop variable has no value outside its frame. */
      vpiHandle first = vpi_handle(vpiForInitStmt, s);
      printf("=%d", c ? value(c) : -1);
      printf(" first_init=%s", first ? vpi_get_str(vpiName, vpi_handle(vpiLhs, first)) : "null");
      targets("init", vpiForInitStmt, s);
    }
    targets("inc", vpiForIncStmt, s);
    printf(" body=%s", lhs ? vpi_get_str(vpiName, lhs) : "null");
    printf("=%d\n", lhs ? value(lhs) : -1);
  }
}
