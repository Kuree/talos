#include "sv_vpi_user.h"
#include <stdio.h>
static void show(const char *name) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)name, 0);
  int guarded = h ? vpi_get(vpiIsProtected, h) : -1;
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  s_vpi_error_info e;
  int refused = vpi_chk_error(&e) != 0;
  printf("%s protected=%d value=%d refused=%d\n", name, guarded, refused ? -1 : v.value.integer, refused);
}
void probe(void) {
  show("top.seen");
  show("top.hidden");
}
