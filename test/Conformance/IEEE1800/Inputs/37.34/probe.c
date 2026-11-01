#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  if (!h)
    return -1;
  vpi_get_value(h, &v);
  return v.value.integer;
}
static const char *first_name(PLI_INT32 relation, vpiHandle h) {
  vpiHandle it = vpi_iterate(relation, h);
  return str(vpiName, it ? vpi_scan(it) : 0);
}
static void items(vpiHandle c) {
  vpiHandle item, it = vpi_iterate(vpiConstraintItem, c);
  if (!it)
    return;
  while ((item = vpi_scan(it))) {
    int type = vpi_get(vpiType, item);
    printf("%s item %s\n", str(vpiName, c), str(vpiType, item));
    if (type == vpiConstraintOrdering) {
      printf("before=%s", first_name(vpiSolveBefore, item));
      printf(" after=%s\n", first_name(vpiSolveAfter, item));
    } else if (type == vpiDistribution) {
      printf("dist expr=%s\n", str(vpiName, vpi_handle(vpiExpr, item)));
      vpiHandle d, dist = vpi_iterate(vpiDistItem, item);
      if (dist)
        while ((d = vpi_scan(dist))) {
          int kind = vpi_get(vpiDistType, d);
          printf("dist item %s=1 weight=%d\n", kind == vpiEqualDist ? "equal" : kind == vpiDivDist ? "divided" : "unknown",
                 value(vpi_handle(vpiWeight, d)));
        }
    }
  }
}
void probe(void) {
  vpiHandle obj = vpi_handle(vpiClassObj, vpi_handle_by_name("top.o", 0));
  vpiHandle c, it = obj ? vpi_iterate(vpiConstraint, obj) : 0;
  if (!it)
    return;
  vpiHandle list[3];
  int n = 0;
  while ((c = vpi_scan(it)) && n < 3) {
    list[n++] = c;
    printf("constraint %s", str(vpiName, c));
    printf(" automatic=%d extern=%d enabled=%d", vpi_get(vpiAutomatic, c), vpi_get(vpiAccessType, c) == vpiExternAcc,
           vpi_get(vpiIsConstraintEnabled, c));
    printf(" parent=%s\n", str(vpiType, vpi_handle(vpiParent, c)));
  }
  for (int i = 0; i < n; i++)
    items(list[i]);
}
