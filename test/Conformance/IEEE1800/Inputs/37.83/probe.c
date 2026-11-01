#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void attributes(const char *where, vpiHandle object) {
  vpiHandle it = object ? vpi_iterate(vpiAttribute, object) : NULL, a;
  if (!it)
    printf("%s: none\n", where);
  while (it && (a = vpi_scan(it))) {
    vpiHandle parent = vpi_handle(vpiParent, a);
    printf("%s: %s", where, vpi_get_str(vpiType, a));
    printf(" name=%s value=%d", vpi_get_str(vpiName, a), value(a));
    /* A statement has no name, so its type identifies it. */
    if (parent && vpi_get(vpiType, parent) == vpiAssignment)
      printf(" parent=%s", vpi_get_str(vpiType, parent));
    else
      printf(" parent=%s", parent ? vpi_get_str(vpiName, parent) : "null");
    printf(" def=%d\n", vpi_get(vpiDefAttribute, a));
  }
}

void probe(void) {
  attributes("v", vpi_handle_by_name("top.v", 0));
  attributes("w", vpi_handle_by_name("top.w", 0));
  attributes("top", vpi_handle_by_name("top", 0));
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle first = vpi_scan(vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)));
  attributes("statement", first);
}
