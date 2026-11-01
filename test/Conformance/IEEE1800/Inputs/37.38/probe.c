#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static void exprs(vpiHandle item) {
  vpiHandle e, it = vpi_iterate(vpiConstraintExpr, item);
  if (it)
    while ((e = vpi_scan(it)))
      printf("expr %s\n", str(vpiDecompile, e));
}
void probe(void) {
  vpiHandle obj = vpi_handle(vpiClassObj, vpi_handle_by_name("top.o", 0));
  vpiHandle cs = obj ? vpi_iterate(vpiConstraint, obj) : 0;
  vpiHandle c = cs ? vpi_scan(cs) : 0;
  vpiHandle item, it = c ? vpi_iterate(vpiConstraintItem, c) : 0;
  if (!it) {
    printf("no constraint items\n");
    return;
  }
  while ((item = vpi_scan(it))) {
    int type = vpi_get(vpiType, item);
    printf("item %s\n", str(vpiType, item));
    if (type == vpiImplication || type == vpiConstrIf || type == vpiConstrIfElse) {
      printf("condition %s\n", str(vpiDecompile, vpi_handle(vpiCondition, item)));
      exprs(item);
    }
    if (type == vpiConstrIfElse) {
      vpiHandle e, elses = vpi_iterate(vpiElseConst, item);
      if (elses)
        while ((e = vpi_scan(elses)))
          printf("else %s\n", str(vpiDecompile, e));
    }
    if (type == vpiOperation) {
      printf("soft=%d", vpi_get(vpiSoft, item));
      printf(" %s\n", str(vpiDecompile, item));
    }
  }
}
