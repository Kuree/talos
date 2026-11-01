#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
void probe(void) {
  vpiHandle top = vpi_handle_by_name("top", 0);
  vpiHandle it = vpi_iterate(vpiVariables, top);
  int n = 0;
  for (vpiHandle h; it && (h = vpi_scan(it)); n++) {
    int type = vpi_get(vpiType, h);
    printf("var %s", vpi_get_str(vpiName, h));
    printf(" type=%s", vpi_get_str(vpiType, h));
    if (type == vpiRealVar) {
      s_vpi_value v = {.format = vpiRealVal};
      vpi_get_value(h, &v);
      printf(" value=%g\n", v.value.real);
    } else if (type == vpiArrayVar) {
      printf(" size=%d\n", vpi_get(vpiSize, h));
    } else if (type == vpiStringVar) {
      s_vpi_value v = {.format = vpiStringVal};
      vpi_get_value(h, &v);
      printf(" size=%d signed=%d value=%s\n", vpi_get(vpiSize, h), vpi_get(vpiSigned, h), v.value.str);
    } else {
      printf(" size=%d signed=%d value=%d\n", vpi_get(vpiSize, h), vpi_get(vpiSigned, h), value(h));
    }
  }
  printf("variables=%d\n", n);
  vpiHandle i = vpi_handle_by_name("top.i", 0);
  printf("lifetime auto=%d alloc=%d\n", vpi_get(vpiAutomatic, i), vpi_get(vpiAllocScheme, i) == vpiOtherScheme);
  // Detail 8: vpiExpr is the initialization expression.
  vpiHandle init = vpi_handle(vpiExpr, i);
  if (init)
    printf("init=%d\n", value(init));
  else
    printf("init=null\n");
  // Details 2, 10 and 18: an element reports vpiArrayMember and its index.
  vpiHandle member = vpi_handle_by_index(vpi_handle_by_name("top.arr", 0), 2);
  vpiHandle index = vpi_scan(vpi_iterate(vpiIndex, member));
  printf("member full=%s", vpi_get_str(vpiFullName, member));
  printf(" array-member=%d index=%d value=%d size=%d\n", vpi_get(vpiArrayMember, member), value(index), value(member),
         vpi_get(vpiSize, member));
  printf("non-member array-member=%d\n", vpi_get(vpiArrayMember, i));
}
