#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static const char *name_of(vpiHandle h) {
  const char *name = h ? vpi_get_str(vpiName, h) : 0;
  return name ? name : "null";
}
static vpiHandle head(const char *variable, const char *path) {
  vpiHandle type = vpi_handle(vpiTypespec, vpi_handle_by_name((PLI_BYTE8 *)path, 0));
  printf("%s type=%s", variable, vpi_get_str(vpiType, type));
  printf(" name=%s", name_of(type));
  return type;
}
void probe(void) {
  // Detail 1: colors -> primary_colors -> NULL.
  vpiHandle c = head("c", "top.c");
  vpiHandle alias = vpi_handle(vpiTypedefAlias, c);
  printf(" alias=%s", name_of(alias));
  printf(" alias-type=%s", vpi_get_str(vpiType, alias));
  printf(" alias-alias=%s\n", name_of(vpi_handle(vpiTypedefAlias, alias)));
  printf("enum");
  vpiHandle it = vpi_iterate(vpiEnumConst, c);
  for (vpiHandle e; it && (e = vpi_scan(it));)
    printf(" %s=%d", vpi_get_str(vpiName, e), value(e));
  printf("\n");
  // Detail 6: an alias inherits the vpiType, and its vpiTypedefAlias is the predefined type.
  vpiHandle t = head("t", "top.t");
  alias = vpi_handle(vpiTypedefAlias, t);
  printf(" alias-type=%s\n", alias ? vpi_get_str(vpiType, alias) : "null");
  head("plain", "top.plain");
  printf("\n");
  // Details 3 and 4: typespec members carry the member's name and type.
  vpiHandle s = head("s", "top.s");
  it = vpi_iterate(vpiTypespecMember, s);
  for (vpiHandle m; it && (m = vpi_scan(it));) {
    printf(" %s", vpi_get_str(vpiName, m));
    printf(":%s", vpi_get_str(vpiType, vpi_handle(vpiTypespec, m)));
  }
  printf("\n");
  // Details 8 and 9: array typespecs unwind through vpiElemTypespec and report the leftmost bounds.
  vpiHandle ar = head("ar", "top.ar");
  printf(" left=%d right=%d", value(vpi_handle(vpiLeftRange, ar)), value(vpi_handle(vpiRightRange, ar)));
  printf(" elem=%s\n", vpi_get_str(vpiType, vpi_handle(vpiElemTypespec, ar)));
  vpiHandle vec = head("vec", "top.vec");
  printf(" left=%d right=%d\n", value(vpi_handle(vpiLeftRange, vec)), value(vpi_handle(vpiRightRange, vec)));
  int n = 0;
  it = vpi_iterate(vpiTypedef, vpi_handle_by_name("top", 0));
  while (it && vpi_scan(it))
    n++;
  printf("typedefs=%d\n", n);
}
