#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static void report(const char *label, const char *name) {
  vpiHandle a = vpi_handle_by_name(name, 0);
  vpiHandle spec = a ? vpi_handle(vpiProperty, a) : 0;
  printf("%s spec=%s", label, str(vpiType, spec));
  if (!spec) {
    printf("\n");
    return;
  }
  printf(" event=%s", str(vpiDecompile, vpi_handle(vpiClockingEvent, spec)));
  printf(" disable=%s", str(vpiDecompile, vpi_handle(vpiDisableCondition, spec)));
  vpiHandle expr = vpi_handle(vpiPropertyExpr, spec);
  printf(" expr=%s\n", str(vpiType, expr));
  if (!expr)
    return;
  int op = vpi_get(vpiOpType, expr);
  printf("overlap_imply=%d nexttime=%d", op == vpiOverlapImplyOp, op == vpiNexttimeOp);
  if (op == vpiNexttimeOp)
    printf(" strong=%d", vpi_get(vpiOpStrong, expr));
  printf("\n");
  int n = 0;
  vpiHandle x, it = vpi_iterate(vpiOperand, expr);
  if (it)
    while ((x = vpi_scan(it))) {
      printf("operand %s\n", str(vpiDecompile, x));
      n++;
    }
  printf("operands=%d\n", n);
}
void probe(void) {
  report("pa", "top.pa");
  report("pn", "top.pn");
  report("pw", "top.pw");
}
