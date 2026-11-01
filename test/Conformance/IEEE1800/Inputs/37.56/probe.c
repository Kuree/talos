#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
void probe(void) {
  vpiHandle a = vpi_handle_by_name("top.ma", 0);
  vpiHandle spec = a ? vpi_handle(vpiProperty, a) : 0;
  vpiHandle expr = spec ? vpi_handle(vpiPropertyExpr, spec) : 0;
  printf("expr=%s\n", str(vpiType, expr));
  int n = 0;
  vpiHandle c, it = expr ? vpi_iterate(vpiClockedSeq, expr) : 0;
  if (it)
    while ((c = vpi_scan(it))) {
      printf("clocked=%s", str(vpiType, c));
      printf(" event=%s", str(vpiDecompile, vpi_handle(vpiClockingEvent, c)));
      printf(" seq=%s\n", str(vpiDecompile, vpi_handle(vpiExpr, c)));
      n++;
    }
  printf("clocked count=%d\n", n);
}
