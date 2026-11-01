#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static vpiHandle expr_of(const char *assertion) {
  vpiHandle a = vpi_handle_by_name(assertion, 0);
  vpiHandle spec = a ? vpi_handle(vpiProperty, a) : 0;
  return spec ? vpi_handle(vpiPropertyExpr, spec) : 0;
}
static int operands(const char *label, vpiHandle op) {
  int n = 0;
  vpiHandle x, it = vpi_iterate(vpiOperand, op);
  if (it)
    while ((x = vpi_scan(it))) {
      printf("%s %s\n", label, str(vpiDecompile, x));
      n++;
    }
  return n;
}
void probe(void) {
  vpiHandle e = expr_of("top.c_int");
  printf("top=%s intersect=%d\n", str(vpiType, e), e && vpi_get(vpiOpType, e) == vpiIntersectOp);
  vpiHandle it = e ? vpi_iterate(vpiOperand, e) : 0;
  vpiHandle inst = it ? vpi_scan(it) : 0, delay = it ? vpi_scan(it) : 0;
  printf("operand0=%s", str(vpiType, inst));
  printf(" decl=%s\n", str(vpiName, inst ? vpi_handle(vpiSequenceDecl, inst) : 0));
  vpiHandle x, args = inst ? vpi_iterate(vpiArgument, inst) : 0;
  if (args)
    while ((x = vpi_scan(args)))
      printf("arg %s\n", str(vpiDecompile, x));
  printf("operand1=%s cycle_delay=%d\n", str(vpiType, delay), delay && vpi_get(vpiOpType, delay) == vpiCycleDelayOp);
  if (delay)
    printf("delay operands=%d\n", operands("delay", delay));
  vpiHandle r = expr_of("top.c_rep");
  printf("repeat=%s consecutive=%d\n", str(vpiType, r), r && vpi_get(vpiOpType, r) == vpiConsecutiveRepeatOp);
  if (r)
    printf("repeat operands=%d\n", operands("operand", r));
}
