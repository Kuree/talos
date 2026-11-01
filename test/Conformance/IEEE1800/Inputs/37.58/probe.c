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
static vpiHandle rhs_of(const char *lhs) {
  vpiHandle c, it = vpi_iterate(vpiContAssign, vpi_handle_by_name("top", 0));
  if (it)
    while ((c = vpi_scan(it)))
      if (!strcmp(str(vpiName, vpi_handle(vpiLhs, c)), lhs))
        return vpi_handle(vpiRhs, c);
  return 0;
}
static void constant_select(const char *label, const char *lhs) {
  vpiHandle s = rhs_of(lhs);
  printf("%s type=%s", label, str(vpiType, s));
  printf(" name=%s", str(vpiName, s));
  printf(" full=%s constant=%d", str(vpiFullName, s), s ? vpi_get(vpiConstantSelect, s) : -1);
  printf(" parent=%s", str(vpiName, s ? vpi_handle(vpiParent, s) : 0));
  printf(" index=%d value=%d\n", value(s ? vpi_handle(vpiIndex, s) : 0), value(s));
}
void describe(void) {
  constant_select("c0", "c0");
  constant_select("param", "param_bit");
}
void dynamic(void) {
  vpiHandle s = rhs_of("dyn"), i = s ? vpi_handle(vpiIndex, s) : 0;
  printf("dyn type=%s constant=%d", str(vpiType, s), s ? vpi_get(vpiConstantSelect, s) : -1);
  printf(" parent=%s", str(vpiName, s ? vpi_handle(vpiParent, s) : 0));
  printf(" index=%s", str(vpiName, i));
  printf(" index_value=%d value=%d\n", value(i), value(s));
}
static void list(const char *label, vpiHandle h) {
  int n = 0;
  vpiHandle x, it = h ? vpi_iterate(vpiUse, h) : 0;
  if (it)
    while ((x = vpi_scan(it))) {
      printf("%s use lhs=%s\n", label, str(vpiName, vpi_handle(vpiLhs, x)));
      n++;
    }
  printf("%s uses=%d\n", label, n);
}
void uses(void) {
  list("vector", vpi_handle_by_name("top.v", 0));
  list("bit", rhs_of("c0"));
}
