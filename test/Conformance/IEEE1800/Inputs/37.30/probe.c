#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static void interface_type(vpiHandle t) {
  printf(" def=%s", vpi_get_str(vpiDefName, t));
  printf(" modport=%d", vpi_get(vpiIsModPort, t));
  // Detail 2: a modport's parent is the interface typespec; an interface's parent is NULL.
  vpiHandle parent = vpi_handle(vpiParent, t);
  printf(" parent=%s", parent ? vpi_get_str(vpiDefName, parent) : "null");
  // Detail 3: the assigned parameter value comes from vpiParamAssign.
  vpiHandle owner = parent ? parent : t;
  vpiHandle it = vpi_iterate(vpiParamAssign, owner);
  for (vpiHandle a; it && (a = vpi_scan(it));) {
    printf(" param %s", vpi_get_str(vpiName, vpi_handle(vpiLhs, a)));
    printf("=%d", value(vpi_handle(vpiRhs, a)));
  }
  printf("\n");
}
void probe(void) {
  int n = 0;
  vpiHandle it = vpi_iterate(vpiTypedef, vpi_handle_by_name("top", 0));
  for (vpiHandle t; it && (t = vpi_scan(it)); n++) {
    printf("typedef %s", vpi_get_str(vpiName, t));
    printf(" type=%s", vpi_get_str(vpiType, t));
    if (vpi_get(vpiType, t) == vpiArrayTypespec) {
      t = vpi_handle(vpiElemTypespec, t);
      printf(" elem=%s", vpi_get_str(vpiType, t));
    }
    interface_type(t);
  }
  printf("typedefs=%d\n", n);
  vpiHandle type = vpi_handle(vpiTypespec, vpi_handle_by_name("top.v", 0));
  printf("var type=%s", vpi_get_str(vpiType, type));
  printf(" def=%s", vpi_get_str(vpiDefName, type));
  printf(" name=%s\n", vpi_get_str(vpiName, type));
}
