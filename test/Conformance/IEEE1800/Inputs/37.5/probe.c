#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static void describe(const char *label, vpiHandle h) {
  printf("%s type=%s", label, vpi_get_str(vpiType, h));
  printf(" name=%s", vpi_get_str(vpiName, h));
  printf(" def=%s", vpi_get_str(vpiDefName, h));
  printf(" full=%s", vpi_get_str(vpiFullName, h));
  printf(" topmodule=%d", vpi_get(vpiTopModule, h));
}
static int count(int relation, vpiHandle h) {
  int n = 0;
  vpiHandle it = vpi_iterate(relation, h);
  while (it && vpi_scan(it))
    n++;
  return n;
}
void probe(void) {
  // Detail 1: top-level modules come from a NULL reference object.
  vpiHandle tops = vpi_iterate(vpiModule, 0);
  vpiHandle top = vpi_scan(tops);
  describe("top", top);
  printf("\ntops after top=%d\n", vpi_scan(tops) != 0);
  vpiHandle it = vpi_iterate(vpiModule, top), u = 0;
  for (vpiHandle h; (h = vpi_scan(it));)
    if (!strcmp(vpi_get_str(vpiName, h), "u"))
      u = h;
  // Detail 2: vpiIndex is NULL outside a module array and the index inside one.
  describe("child", u);
  printf(" index=%s\n", vpi_handle(vpiIndex, u) ? "set" : "null");
  vpiHandle element = vpi_handle_by_name("top.a[1]", 0);
  printf("element full=%s", vpi_get_str(vpiFullName, element));
  printf(" def=%s", vpi_get_str(vpiDefName, element));
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(vpi_handle(vpiIndex, element), &v);
  printf(" index=%d\n", v.value.integer);
  vpiHandle scope = vpi_scan(vpi_iterate(vpiInternalScope, u));
  printf("internal scope=%s", vpi_get_str(vpiName, scope));
  printf(" inside=%s\n", vpi_get_str(vpiFullName, vpi_handle(vpiScope, scope)));
  vpiHandle port = vpi_scan(vpi_iterate(vpiPort, u));
  printf("port=%s contassigns=%d\n", vpi_get_str(vpiName, port), count(vpiContAssign, u));
}
