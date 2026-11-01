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

static void condition(vpiHandle control) {
  vpiHandle c = vpi_handle(vpiCondition, control);
  printf(" condition=%s", c ? vpi_get_str(vpiType, c) : "null");
  if (!c)
    return;
  if (vpi_get(vpiType, c) == vpiOperation) {
    int op = vpi_get(vpiOpType, c);
    vpiHandle it = vpi_iterate(vpiOperand, c);
    vpiHandle operand = it ? vpi_scan(it) : NULL;
    printf(" op=%s", op == vpiPosedgeOp ? "posedge" : op == vpiNegedgeOp ? "negedge" : "other");
    printf(" operand=%s", operand ? vpi_get_str(vpiName, operand) : "null");
  } else
    printf(" name=%s", vpi_get_str(vpiName, c));
}

void probe(void) {
  vpiHandle procs = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  while ((p = vpi_scan(procs))) {
    vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
    while (it && (s = vpi_scan(it))) {
      int type = vpi_get(vpiType, s);
      if (type == vpiEventControl) {
        vpiHandle stmt = vpi_handle(vpiStmt, s);
        printf("%s", vpi_get_str(vpiType, s));
        condition(s);
        printf(" stmt=%s", stmt ? vpi_get_str(vpiType, stmt) : "null");
        show_lhs("lhs", stmt);
        printf("\n");
      } else if (type == vpiAssignment) {
        vpiHandle control = vpi_handle(vpiEventControl, s);
        printf("assignment control=%s", control ? vpi_get_str(vpiType, control) : "null");
        if (control) {
          vpiHandle stmt = vpi_handle(vpiStmt, control);
          condition(control);
          printf(" stmt=%s", stmt ? vpi_get_str(vpiType, stmt) : "null");
        }
        show_lhs("lhs", s);
        printf("\n");
      }
    }
  }
}
