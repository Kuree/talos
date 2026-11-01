#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  printf("u is vpiModule=%d\n", vpi_get(vpiType, vpi_handle_by_name("top.u", 0)) == vpiModule);
  printf("b is vpiInterface=%d\n", vpi_get(vpiType, vpi_handle_by_name("top.b", 0)) == vpiInterface);
}
