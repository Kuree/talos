#include "sv_vpi_user.h"
#include <stdio.h>
static void show(const char *label, const char *path) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
  if (!h) {
    printf("%s null\n", label);
    return;
  }
  printf("%s type=%s", label, vpi_get_str(vpiType, h));
  printf(" protected=%d", vpi_get(vpiIsProtected, h));
  const char *name = vpi_get_str(vpiName, h);
  s_vpi_error_info info;
  int error = vpi_chk_error(&info) != 0;
  printf(" name=%s error=%d\n", name ? name : "null", error);
}
void probe(void) {
  show("plain", "top.plain");
  show("hidden", "top.s.hidden");
}
