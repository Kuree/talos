#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static const char *case_type(vpiHandle s) {
  switch (vpi_get(vpiCaseType, s)) {
  case vpiCaseExact: return "exact";
  case vpiCaseX: return "casex";
  case vpiCaseZ: return "casez";
  }
  return "other";
}

static const char *qualifier(vpiHandle s) {
  switch (vpi_get(vpiQualifier, s)) {
  case vpiNoQualifier: return "none";
  case vpiUniqueQualifier: return "unique";
  case vpiPriorityQualifier: return "priority";
  case vpiTaggedQualifier: return "tagged";
  }
  return "other";
}

static void item(vpiHandle c, vpiHandle i) {
  vpiHandle it = vpi_iterate(vpiExpr, i), e, stmt = vpi_handle(vpiStmt, i);
  printf("item of %s/%s", case_type(c), qualifier(c));
  if (!it)
    printf(" exprs=null");
  for (int first = 1; it && (e = vpi_scan(it)); first = 0) {
    int type = vpi_get(vpiType, e);
    if (type == vpiAnyPattern || type == vpiTaggedPattern || type == vpiStructPattern)
      printf(" pattern=%s", vpi_get_str(vpiType, e));
    else
      printf("%s%d,", first ? " exprs=" : "", value(e));
  }
  vpiHandle lhs = stmt ? vpi_handle(vpiLhs, stmt) : NULL;
  if (lhs) {
    printf(" stmt=%s", vpi_get_str(vpiName, lhs));
    printf("=%d\n", value(lhs));
  } else
    printf(" stmt=%s\n", stmt ? "none" : "null");
}

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    if (vpi_get(vpiType, s) != vpiCase)
      continue;
    vpiHandle c = vpi_handle(vpiCondition, s), items = vpi_iterate(vpiCaseItem, s), i;
    printf("%s type=%s qualifier=%s", vpi_get_str(vpiType, s), case_type(s), qualifier(s));
    printf(" condition=%s", c ? vpi_get_str(vpiName, c) : "null");
    printf("=%d\n", c ? value(c) : -1);
    while (items && (i = vpi_scan(items)))
      item(s, i);
  }
}
