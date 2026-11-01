#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static const char *qualifier(vpiHandle s) {
  switch (vpi_get(vpiQualifier, s)) {
  case vpiNoQualifier: return "none";
  case vpiUniqueQualifier: return "unique";
  case vpiPriorityQualifier: return "priority";
  }
  return "other";
}

static void branch(const char *label, vpiHandle s) {
  vpiHandle lhs = s ? vpi_handle(vpiLhs, s) : NULL;
  printf(" %s=%s", label, lhs ? vpi_get_str(vpiName, lhs) : "null");
  if (lhs)
    printf("=%d", value(lhs));
}

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type != vpiIf && type != vpiIfElse)
      continue;
    vpiHandle c = vpi_handle(vpiCondition, s);
    printf("%s qualifier=%s", vpi_get_str(vpiType, s), qualifier(s));
    printf(" condition=%s", c ? vpi_get_str(vpiType, c) : "null");
    printf("=%d", c ? value(c) : -1);
    branch("stmt", vpi_handle(vpiStmt, s));
    branch("else", type == vpiIfElse ? vpi_handle(vpiElseStmt, s) : NULL);
    printf("\n");
  }
}
