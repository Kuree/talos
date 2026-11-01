#include "sv_vpi_user.h"
#include <stdio.h>
static const char *name_of(vpiHandle h) { return h ? vpi_get_str(vpiName, h) : "null"; }
void probe(void) {
  int declared = 0;
  // 37.10 detail 10: vpiNetTypedef returns the nettypes declared in the instance.
  vpiHandle it = vpi_iterate(vpiNetTypedef, vpi_handle_by_name("top", 0));
  for (vpiHandle n; it && (n = vpi_scan(it)); declared++) {
    vpiHandle type = vpi_handle(vpiTypespec, n);
    printf("nettype name=%s", vpi_get_str(vpiName, n));
    printf(" type=%s", type ? vpi_get_str(vpiType, type) : "null");
    printf(" with=%s", name_of(vpi_handle(vpiWith, n)));
    printf(" alias=%s\n", name_of(vpi_handle(vpiNetTypedefAlias, n)));
  }
  printf("declared=%d\n", declared);
  vpiHandle n = vpi_handle_by_name("top.n", 0);
  s_vpi_value v = {.format = vpiRealVal};
  vpi_get_value(n, &v);
  printf("net summed value=%g nettype-net=%d\n", v.value.real, vpi_get(vpiNetType, n) == vpiNettypeNet);
}
