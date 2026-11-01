#include "sv_vpi_user.h"
#include <stdio.h>
static int type_of(const char *name) { return vpi_get(vpiType, vpi_handle_by_name((PLI_BYTE8 *)name, 0)); }
void probe(void) {
  printf("type codes module=%d net=%d reg=%d integer=%d parameter=%d\n", type_of("top"), type_of("top.w"), type_of("top.r"),
         type_of("top.i"), type_of("top.P"));
  printf("property codes type=%d name=%d fullname=%d size=%d defname=%d\n", vpiType, vpiName, vpiFullName, vpiSize, vpiDefName);
  printf("format codes bin=%d int=%d\n", vpiBinStrVal, vpiIntVal);
  vpiHandle w = vpi_handle_by_name("top.w", 0);
  s_vpi_value v = {.format = vpiBinStrVal};
  vpi_get_value(w, &v);
  printf("net size=%d value=%s\n", vpi_get(vpiSize, w), v.value.str);
}
