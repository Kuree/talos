#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

void probe(const char *when) {
  vpiHandle tf = vpi_handle(vpiActiveTimeFormat, NULL);
  printf("%s:", when);
  if (!tf) {
    printf(" null\n");
    return;
  }
  printf(" %s", vpi_get_str(vpiType, tf));
  printf(" name=%s args=", vpi_get_str(vpiName, tf));
  /* Argument 2 is the suffix string; the integers identify which call this is. */
  vpiHandle it = vpi_iterate(vpiArgument, tf), a;
  for (int i = 0; it && (a = vpi_scan(it)); ++i)
    if (i != 2)
      printf(i == 3 ? "%d" : "%d,", value(a));
  printf("\n");
}
