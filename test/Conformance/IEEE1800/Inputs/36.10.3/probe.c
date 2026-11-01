#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static void traverse(vpiHandle expr, int depth) {
  if (vpi_get(vpiType, expr) == vpiOperation) {
    int op = vpi_get(vpiOpType, expr);
    printf("%*soperation mult=%d add=%d value=%d\n", depth, "", op == vpiMultOp, op == vpiAddOp, value(expr));
    vpiHandle it = vpi_iterate(vpiOperand, expr), sub;
    while (it && (sub = vpi_scan(it)))
      traverse(sub, depth + 2);
    return;
  }
  printf("%*sleaf %s", depth, "", vpi_get_str(vpiName, expr));
  printf(" value=%d\n", value(expr));
}
void probe(void) {
  vpiHandle assigns = vpi_iterate(vpiContAssign, vpi_handle_by_name("top", 0));
  traverse(vpi_handle(vpiRhs, vpi_scan(assigns)), 0);
  puts("traversed");
}
