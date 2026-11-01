#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
void probe(void) {
  vpiHandle it = vpi_iterate(vpiRange, vpi_handle_by_name("top.v", 0));
  vpiHandle r = vpi_scan(it);
  printf("type=%s", vpi_get_str(vpiType, r));
  printf(" left=%d right=%d\n", value(vpi_handle(vpiLeftRange, r)), value(vpi_handle(vpiRightRange, r)));
  it = vpi_iterate(vpiRange, vpi_handle_by_name("top.w", 0));
  vpiHandle o = vpi_scan(it), i = vpi_scan(it);
  printf("outer=[%d:%d] inner=[%d:%d] more=%d\n", value(vpi_handle(vpiLeftRange, o)),
         value(vpi_handle(vpiRightRange, o)), value(vpi_handle(vpiLeftRange, i)),
         value(vpi_handle(vpiRightRange, i)), vpi_scan(it) != 0);
}
