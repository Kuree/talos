#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
// 5.6.1: the escaped spelling \w (with its terminating space) names the same identifier as w.
static void plain(const char *s) {
  for (; *s; s++) {
    if (*s != '\\') {
      putchar(*s);
      continue;
    }
    while (*++s && *s != ' ')
      putchar(*s);
    if (!*s)
      break;
  }
}
static void report(char *net) {
  vpiHandle n = vpi_handle_by_name(net, 0), x, it = vpi_iterate(vpiDriver, n);
  int count = 0;
  if (it)
    while ((x = vpi_scan(it))) {
      printf("%s driver %s\n", net, str(vpiType, x));
      count++;
    }
  printf("%s drivers=%d\n", net, count);
  count = 0;
  it = vpi_iterate(vpiLoad, n);
  if (it)
    while ((x = vpi_scan(it))) {
      printf("%s load %s", net, str(vpiType, x));
      if (vpi_get(vpiType, x) == vpiPort) {
        printf(" high=");
        plain(str(vpiDecompile, vpi_handle(vpiHighConn, x)));
      }
      printf("\n");
      count++;
    }
  printf("%s loads=%d\n", net, count);
}
void probe(void) {
  report("top.w");
  report("top.from_port");
  report("top.quiet");
}
