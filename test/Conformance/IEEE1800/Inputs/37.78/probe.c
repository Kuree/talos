#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

/* A task or function with several statements has an unnamed begin for vpiStmt (37.12 detail 5). */
static vpiHandle find_return(vpiHandle taskfunc) {
  vpiHandle stmt = vpi_handle(vpiStmt, taskfunc), it, s;
  if (!stmt || vpi_get(vpiType, stmt) != vpiBegin)
    return stmt;
  it = vpi_iterate(vpiStmt, stmt);
  while (it && (s = vpi_scan(it)))
    if (vpi_get(vpiType, s) == vpiReturnStmt)
      return s;
  return NULL;
}

static void show(const char *path) {
  vpiHandle tf = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
  if (!tf) {
    printf("%s=null\n", path);
    return;
  }
  vpiHandle ret = find_return(tf);
  printf("%s", vpi_get_str(vpiType, tf));
  printf(" stmt=%s", ret ? vpi_get_str(vpiType, ret) : "null");
  vpiHandle c = ret ? vpi_handle(vpiCondition, ret) : NULL;
  if (c) {
    printf(" condition=%s", vpi_get(vpiOpType, c) == vpiAddOp ? "vpiAddOp" : "other");
    printf(" value=%d\n", value(c));
  } else
    printf(" condition=null\n");
}

void probe(void) {
  show("top.f");
  show("top.t");
}
