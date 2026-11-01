#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static void element(const char *label, vpiHandle e) {
  printf("%s full=%s", label, vpi_get_str(vpiFullName, e));
  printf(" out=%d\n", value(vpi_handle_by_name("out", e)));
}
void probe(void) {
  vpiHandle u = vpi_handle_by_name("top.u", 0);
  printf("array type=%s", vpi_get_str(vpiType, u));
  printf(" name=%s", vpi_get_str(vpiName, u));
  printf(" full=%s", vpi_get_str(vpiFullName, u));
  printf(" size=%d left=%d right=%d\n", vpi_get(vpiSize, u), value(vpi_handle(vpiLeftRange, u)),
         value(vpi_handle(vpiRightRange, u)));
  element("by index", vpi_handle_by_index(u, 2));
  int n = 0;
  vpiHandle it = vpi_iterate(vpiModule, u);
  while (it && vpi_scan(it))
    n++;
  printf("elements=%d\n", n);
  vpiHandle b = vpi_handle_by_name("top.b", 0);
  printf("interface array type=%s size=%d\n", vpi_get_str(vpiType, b), vpi_get(vpiSize, b));
  // Detail 2: vpiRange runs leftmost to rightmost; vpiLeftRange/vpiRightRange give the leftmost dimension.
  vpiHandle m = vpi_handle_by_name("top.m", 0);
  it = vpi_iterate(vpiRange, m);
  vpiHandle first = vpi_scan(it), second = vpi_scan(it);
  printf("ranges [%d:%d] [%d:%d] left=%d right=%d\n", value(vpi_handle(vpiLeftRange, first)),
         value(vpi_handle(vpiRightRange, first)), value(vpi_handle(vpiLeftRange, second)),
         value(vpi_handle(vpiRightRange, second)), value(vpi_handle(vpiLeftRange, m)),
         value(vpi_handle(vpiRightRange, m)));
  PLI_INT32 indices[2] = {0, 3};
  element("by multi index", vpi_handle_by_multi_index(m, 2, indices));
}
