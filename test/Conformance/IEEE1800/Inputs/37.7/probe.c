#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  vpiHandle it = vpi_iterate(vpiModport, vpi_handle_by_name("top.b", 0));
  for (vpiHandle m; it && (m = vpi_scan(it));) {
    printf("modport type=%s", vpi_get_str(vpiType, m));
    printf(" name=%s", vpi_get_str(vpiName, m));
    printf(" in=%s", vpi_get_str(vpiFullName, vpi_handle(vpiInterface, m)));
    vpiHandle decls = vpi_iterate(vpiIODecl, m);
    for (vpiHandle d; decls && (d = vpi_scan(decls));) {
      int direction = vpi_get(vpiDirection, d);
      printf(" %s:%s", vpi_get_str(vpiName, d),
             direction == vpiInput ? "input" : direction == vpiOutput ? "output" : "other");
    }
    printf("\n");
  }
}
