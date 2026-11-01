#include "sv_vpi_user.h"
#include <stdio.h>
static vpiHandle find(const char *name) { return vpi_handle_by_name((PLI_BYTE8 *)name, 0); }
void probe(void) {
  vpiHandle w = find("top.w"), obj = vpi_handle(vpiClassObj, w);
  printf("interface=%d longint=%d class var=%d bit=%d class obj=%d assert=%d\n", vpi_get(vpiType, find("top.i")),
         vpi_get(vpiType, find("top.l")), vpi_get(vpiType, w), vpi_get(vpiType, find("top.b")), vpi_get(vpiType, obj),
         vpi_get(vpiType, find("top.check")));
  printf("object id nonzero=%d\n", vpi_get(vpiObjId, obj) != 0);
}
