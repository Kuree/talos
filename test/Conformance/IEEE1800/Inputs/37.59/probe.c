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
// 5.6.1: the escaped spelling \a (with its terminating space) names the same identifier as a.
static void plain(const char *s) {
  for (; *s; s++) {
    if (*s != '\\') {
      putchar(*s);
      continue;
    }
    while (*++s && *s != ' ')
      putchar(*s);
    if (!*s)
      break;
  }
}
static vpiHandle rhs_of(const char *lhs) {
  vpiHandle c, it = vpi_iterate(vpiContAssign, vpi_handle_by_name("top", 0));
  if (it)
    while ((c = vpi_scan(it)))
      if (!strcmp(str(vpiName, vpi_handle(vpiLhs, c)), lhs))
        return vpi_handle(vpiRhs, c);
  return 0;
}
static vpiHandle operand(vpiHandle op, int index) {
  vpiHandle x = 0, it = op ? vpi_iterate(vpiOperand, op) : 0;
  for (int i = 0; it && i <= index; i++)
    x = vpi_scan(it);
  return x;
}
static void operands(vpiHandle op) {
  vpiHandle x, it = op ? vpi_iterate(vpiOperand, op) : 0;
  if (it)
    while ((x = vpi_scan(it))) {
      printf("operand %s", str(vpiType, x));
      printf(" value=%d\n", value(x));
    }
}
void describe(void) {
  vpiHandle e = rhs_of("sum");
  printf("sum type=%s add=%d size=%d text=", str(vpiType, e), vpi_get(vpiOpType, e) == vpiAddOp, vpi_get(vpiSize, e));
  plain(str(vpiDecompile, e));
  printf(" value=%d\n", value(e));
  operands(e);

  e = rhs_of("product");
  printf("product mult=%d text=", vpi_get(vpiOpType, e) == vpiMultOp);
  plain(str(vpiDecompile, e));
  printf(" value=%d\n", value(e));

  e = rhs_of("rep");
  printf("rep multi_concat=%d\n", vpi_get(vpiOpType, e) == vpiMultiConcatOp);
  operands(e);

  int integer = vpi_get(vpiConstType, operand(e, 0));
  vpiHandle text = operand(rhs_of("is_hi"), 1), real = operand(rhs_of("is_big"), 1);
  printf("const integer=%d string=%d real=%d\n",
         integer == vpiDecConst || integer == vpiBinaryConst || integer == vpiOctConst || integer == vpiHexConst ||
             integer == vpiIntConst,
         text && vpi_get(vpiConstType, text) == vpiStringConst, real && vpi_get(vpiConstType, real) == vpiRealConst);

  e = rhs_of("part");
  printf("part type=%s constant=%d", str(vpiType, e), vpi_get(vpiConstantSelect, e));
  printf(" parent=%s", str(vpiName, vpi_handle(vpiParent, e)));
  printf(" left=%d right=%d value=%d\n", value(vpi_handle(vpiLeftRange, e)), value(vpi_handle(vpiRightRange, e)), value(e));

  e = rhs_of("indexed");
  printf("indexed type=%s constant=%d positive=%d", str(vpiType, e), vpi_get(vpiConstantSelect, e),
         vpi_get(vpiIndexedPartSelectType, e) == vpiPosIndexed);
  printf(" parent=%s", str(vpiName, vpi_handle(vpiParent, e)));
  printf(" base=%s", str(vpiName, vpi_handle(vpiBaseExpr, e)));
  printf(" width=%d value=%d\n", value(vpi_handle(vpiWidthExpr, e)), value(e));

  e = rhs_of("casted");
  printf("cast is_cast=%d", vpi_get(vpiOpType, e) == vpiCastOp);
  printf(" typespec=%s operand=", str(vpiType, vpi_handle(vpiTypespec, e)));
  plain(str(vpiDecompile, operand(e, 0)));
  printf(" value=%d\n", value(e));
}
void after(void) {
  printf("after sum=%d product=%d part=%d indexed=%d\n", value(rhs_of("sum")), value(rhs_of("product")), value(rhs_of("part")),
         value(rhs_of("indexed")));
}
