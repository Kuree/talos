#include "sv_vpi_user.h"
#include <stdio.h>
static int present(const char *name) {
  vpiHandle it = vpi_iterate(vpiVariables, vpi_handle_by_name("top", 0)), h;
  int found = 0;
  while (it && (h = vpi_scan(it))) {
    const char *full = vpi_get_str(vpiName, h);
    int match = 1;
    for (const char *a = full, *b = name; *a || *b; a++, b++)
      if (*a != *b) {
        match = 0;
        break;
      }
    found |= match;
  }
  return found;
}
void probe(void) {
  printf("r in vpiVariables=%d\n", present("r"));
  printf("m in vpiVariables=%d\n", present("m"));
  vpiHandle ia = vpi_handle_by_name("top.ia", 0);
  printf("ia is vpiRegArray=%d\n", vpi_get(vpiType, ia) == vpiRegArray);
  vpiHandle it = vpi_iterate(vpiReg, ia);
  vpiHandle element = it ? vpi_scan(it) : 0;
  printf("ia element is vpiIntegerVar=%d\n", element && vpi_get(vpiType, element) == vpiIntegerVar);
}
