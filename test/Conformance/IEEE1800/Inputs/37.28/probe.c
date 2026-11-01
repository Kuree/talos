#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static const char *type_of(vpiHandle h) { return h ? vpi_get_str(vpiType, h) : "null"; }
static vpiHandle param(const char *name) {
  vpiHandle it = vpi_iterate(vpiParameter, vpi_handle_by_name("top.u", 0)), found = 0;
  for (vpiHandle p; it && (p = vpi_scan(it));)
    if (!strcmp(vpi_get_str(vpiName, p), name))
      found = p;
  return found;
}
// Details 1, 3 and 5: value at end of elaboration, default expression, NULL range unless explicit.
static void value_param(const char *name) {
  vpiHandle p = param(name);
  printf("%s type=%s", name, type_of(p));
  printf(" full=%s", vpi_get_str(vpiFullName, p));
  vpiHandle fallback = vpi_handle(vpiExpr, p), left = vpi_handle(vpiLeftRange, p);
  printf(" value=%d", value(p));
  if (fallback)
    printf(" default=%d", value(fallback));
  else
    printf(" default=null");
  printf(" size=%d signed=%d local=%d", vpi_get(vpiSize, p), vpi_get(vpiSigned, p), vpi_get(vpiLocalParam, p));
  if (left)
    printf(" left=%d\n", value(left));
  else
    printf(" left=null\n");
}
static void param_assigns(vpiHandle owner) {
  vpiHandle it = vpi_iterate(vpiParamAssign, owner);
  for (vpiHandle a; it && (a = vpi_scan(it));) {
    vpiHandle lhs = vpi_handle(vpiLhs, a), rhs = vpi_handle(vpiRhs, a);
    printf("param assign lhs=%s", vpi_get_str(vpiFullName, lhs));
    if (vpi_get(vpiType, lhs) == vpiTypeParameter)
      printf(" typespec=%s", type_of(rhs));
    else
      printf(" rhs=%d", value(rhs));
    printf(" byname=%d\n", vpi_get(vpiConnByName, a));
  }
}
void probe(void) {
  value_param("P");
  value_param("Q");
  vpiHandle l = param("L");
  printf("L type=%s value=%d local=%d\n", type_of(l), value(l), vpi_get(vpiLocalParam, l));
  vpiHandle r = param("R");
  if (r) {
    s_vpi_value real = {.format = vpiRealVal};
    vpi_get_value(r, &real);
    printf("real const=%d value=%g\n", vpi_get(vpiConstType, r) == vpiRealConst, real.value.real);
  } else {
    printf("real null\n");
  }
  // Details 2 and 3: a type parameter's typespec is the resolved one, vpiExpr the default.
  vpiHandle t = param("T");
  printf("type param type=%s", type_of(t));
  printf(" typespec=%s", type_of(vpi_handle(vpiTypespec, t)));
  printf(" default=%s\n", type_of(vpi_handle(vpiExpr, t)));
  // Detail 4: vpiLhs is the overridden parameter. The clause does not say which instance owns
  // the assignment, so accept either the instance or its parent.
  param_assigns(vpi_handle_by_name("top.u", 0));
  param_assigns(vpi_handle_by_name("top", 0));
  vpiHandle it = vpi_iterate(vpiDefParam, vpi_handle_by_name("top", 0));
  vpiHandle d = it ? vpi_scan(it) : 0;
  if (d) {
    vpiHandle lhs = vpi_handle(vpiLhs, d);
    printf("def param type=%s", vpi_get_str(vpiType, d));
    printf(" lhs=%s rhs=%d", vpi_get_str(vpiFullName, lhs), value(vpi_handle(vpiRhs, d)));
    printf(" elaborated=%d\n", value(lhs));
  } else {
    printf("def param null elaborated=%d\n", value(vpi_handle_by_name("top.v.Q", 0)));
  }
  vpiHandle sp = vpi_handle_by_name("top.u.sp", 0);
  if (sp)
    printf("spec param type=%s value=%d\n", vpi_get_str(vpiType, sp), value(sp));
  else
    printf("spec param null\n");
}
