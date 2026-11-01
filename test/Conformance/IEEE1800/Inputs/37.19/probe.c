#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
// A var select appears as the right-hand side of the continuous assignment to `lhs`.
static vpiHandle select_of(const char *lhs) {
  vpiHandle it = vpi_iterate(vpiContAssign, vpi_handle_by_name("top", 0));
  vpiHandle found = 0;
  for (vpiHandle a; it && (a = vpi_scan(it));)
    if (!strcmp(vpi_get_str(vpiName, vpi_handle(vpiLhs, a)), lhs))
      found = vpi_handle(vpiRhs, a);
  return found;
}
void show(const char *which, const char *lhs) {
  vpiHandle s = select_of(lhs);
  if (!s) {
    printf("%s null\n", which);
    return;
  }
  printf("%s type=%s", which, vpi_get_str(vpiType, s));
  int constant = vpi_get(vpiConstantSelect, s);
  if (constant)
    printf(" full=%s", vpi_get_str(vpiFullName, s));
  printf(" parent=%s", vpi_get_str(vpiFullName, vpi_handle(vpiParent, s)));
  printf(" size=%d constant=%d index=%d value=%d\n", vpi_get(vpiSize, s), constant, value(vpi_handle(vpiIndex, s)), value(s));
}
void put(void) {
  s_vpi_value v = {.format = vpiIntVal, .value = {.integer = 7}};
  vpiHandle s = select_of("by_const");
  if (s)
    vpi_put_value(s, &v, 0, vpiNoDelay);
}
