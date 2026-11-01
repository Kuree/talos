#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
void probe(void) {
  // 37.16 details 12 and 13 and 37.24 detail 1.
  vpiHandle ic = vpi_handle_by_name("top.ic", 0);
  vpiHandle type = vpi_handle(vpiTypespec, ic);
  printf("net type=%s", vpi_get_str(vpiType, ic));
  printf(" nettype=%d resolved=%d", vpi_get(vpiNetType, ic) == vpiInterconnect, vpi_get(vpiResolvedNetType, ic) == vpiWire);
  printf(" typespec=%s size=%d\n", type ? vpi_get_str(vpiType, type) : "null", vpi_get(vpiSize, ic));
  vpiHandle ia = vpi_handle_by_name("top.ia", 0);
  printf("array type=%s", vpi_get_str(vpiType, ia));
  printf(" packed=%d size=%d left=%d right=%d typespec=%s\n", vpi_get(vpiPacked, ia), vpi_get(vpiSize, ia),
         value(vpi_handle(vpiLeftRange, ia)), value(vpi_handle(vpiRightRange, ia)),
         vpi_handle(vpiTypespec, ia) ? "set" : "null");
  int n = 0;
  vpiHandle it = vpi_iterate(vpiElement, ia), first = 0;
  for (vpiHandle e; it && (e = vpi_scan(it)); n++)
    if (!first)
      first = e;
  printf("elements=%d first=%s\n", n, first ? vpi_get_str(vpiType, first) : "null");
  printf("through sink i=%d j=%d k=%d\n", value(vpi_handle_by_name("top.s.i", 0)),
         value(vpi_handle_by_name("top.s0.i", 0)), value(vpi_handle_by_name("top.s1.i", 0)));
}
