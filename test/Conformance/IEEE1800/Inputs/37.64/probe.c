#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static vpiHandle block(void) {
  vpiHandle it = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  while ((p = vpi_scan(it))) {
    vpiHandle s = vpi_handle(vpiStmt, p);
    if (s && vpi_get(vpiType, s) == vpiBegin)
      return s;
  }
  return NULL;
}

static const char *op_name(int op) {
  return op == vpiAssignmentOp ? "vpiAssignmentOp" : op == vpiAddOp ? "vpiAddOp" : "other";
}

static void control(vpiHandle s) {
  vpiHandle d = vpi_handle(vpiDelayControl, s), e = vpi_handle(vpiEventControl, s),
            r = vpi_handle(vpiRepeatControl, s), c = d ? d : e ? e : r;
  printf(" control=%s\n", c ? vpi_get_str(vpiType, c) : "none");
}

void probe(void) {
  vpiHandle it = vpi_iterate(vpiStmt, block()), s;
  while ((s = vpi_scan(it))) {
    if (vpi_get(vpiType, s) != vpiAssignment)
      continue;
    vpiHandle lhs = vpi_handle(vpiLhs, s), rhs = vpi_handle(vpiRhs, s);
    printf("%s", vpi_get_str(vpiType, s));
    printf(" blocking=%d op=%s", vpi_get(vpiBlocking, s), op_name(vpi_get(vpiOpType, s)));
    printf(" lhs=%s", lhs ? vpi_get_str(vpiName, lhs) : "null");
    if (lhs)
      printf("=%d", value(lhs));
    if (rhs)
      printf(" rhs=%d", value(rhs));
    else
      printf(" rhs=null");
    control(s);
  }
}
