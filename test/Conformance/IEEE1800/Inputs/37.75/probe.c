#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

/* The variable an assignment statement writes, with its current value. */
static void show_lhs(const char *label, vpiHandle s) {
  vpiHandle lhs = s ? vpi_handle(vpiLhs, s) : NULL;
  printf(" %s=%s", label, lhs ? vpi_get_str(vpiName, lhs) : "null");
  if (lhs)
    printf("=%d", value(lhs));
}

static void show_foreach(vpiHandle s) {
  vpiHandle arrays = vpi_iterate(vpiVariables, s), array = arrays ? vpi_scan(arrays) : NULL;
  vpiHandle it = vpi_iterate(vpiLoopVars, s), v;
  printf("%s", vpi_get_str(vpiType, s));
  printf(" array=%s vars=", array ? vpi_get_str(vpiName, array) : "null");
  while (it && (v = vpi_scan(it))) {
    if (vpi_get(vpiType, v) == vpiOperation && vpi_get(vpiOpType, v) == vpiNullOp)
      printf("skipped,");
    else
      printf("%s,", vpi_get_str(vpiName, v));
  }
  show_lhs("stmt", vpi_handle(vpiStmt, s));
  printf("\n");
}

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type == vpiForeachStmt)
      show_foreach(s);
    else if (type == vpiDoWhile) {
      vpiHandle c = vpi_handle(vpiCondition, s);
      printf("%s", vpi_get_str(vpiType, s));
      printf(" condition=%s", !c ? "null" : vpi_get(vpiOpType, c) == vpiLtOp ? "vpiLtOp" : "other");
      printf("=%d", c ? value(c) : -1);
      show_lhs("stmt", vpi_handle(vpiStmt, s));
      printf("\n");
    }
  }
}
