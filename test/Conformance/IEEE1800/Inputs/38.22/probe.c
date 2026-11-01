#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static vpiHandle port(const char *instance, const char *name) {
  vpiHandle it = vpi_iterate(vpiPort, vpi_handle_by_name((PLI_BYTE8 *)instance, 0));
  for (vpiHandle p; it && (p = vpi_scan(it));) {
    if (!strcmp(vpi_get_str(vpiName, p), name)) {
      vpi_release_handle(it);
      return p;
    }
  }
  return NULL;
}
void probe(void) {
  vpiHandle out = port("top.src", "o"), in = port("top.dst", "i"), wide = port("top.dst", "wide");
  vpiHandle path = vpi_handle_multi(vpiInterModPath, out, in);
  if (!path) { printf("path=null\n"); return; }
  printf("type=%s\n", vpi_get_str(vpiType, path));
  int count = 0;
  vpiHandle ports = vpi_iterate(vpiPorts, path);
  for (vpiHandle p; ports && (p = vpi_scan(ports)); count++)
    printf("port%d=%s\n", count, vpi_get_str(vpiFullName, p));
  printf("ports=%d same_again=%d\n", count,
         vpi_compare_objects(path, vpi_handle_multi(vpiInterModPath, out, in)));
  // "The ports shall be of the same size."
  printf("wider=%s\n", vpi_handle_multi(vpiInterModPath, out, wide) ? "live" : "null");
}
