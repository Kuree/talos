#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
void probe(void) {
  int n = 0;
  vpiHandle a, it = vpi_iterate(vpiAssertion, vpi_handle_by_name("top", 0));
  if (it)
    while ((a = vpi_scan(it))) {
      printf("assertion type=%s", str(vpiType, a));
      printf(" name=%s line=%d", str(vpiName, a), vpi_get(vpiStartLine, a));
      printf(" file=%d\n", strstr(str(vpiFile, a), ".sv") != 0);
      n++;
    }
  printf("instance count=%d\n", n);
  n = 0;
  it = vpi_iterate(vpiAssertion, NULL);
  if (it)
    while (vpi_scan(it))
      n++;
  printf("design count=%d\n", n);
  printf("by name=%s\n", str(vpiType, vpi_handle_by_name("top.p_cover", 0)));
}
