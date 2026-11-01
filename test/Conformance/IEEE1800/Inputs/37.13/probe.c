#include "sv_vpi_user.h"
#include <stdio.h>
static const char *direction(int d) {
  return d == vpiInput ? "input" : d == vpiOutput ? "output" : d == vpiInout ? "inout" : d == vpiRef ? "ref" : "other";
}
static void bound(const char *label, vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  if (h) {
    vpi_get_value(h, &v);
    printf(" %s=%d", label, v.value.integer);
  } else {
    printf(" %s=null", label);
  }
}
static void decls(vpiHandle owner, int read) {
  vpiHandle it = vpi_iterate(vpiIODecl, owner);
  for (vpiHandle d; it && (d = vpi_scan(it));) {
    printf("io %s", vpi_get_str(vpiName, d));
    printf(" dir=%s size=%d signed=%d scalar=%d vector=%d", direction(vpi_get(vpiDirection, d)), vpi_get(vpiSize, d),
           vpi_get(vpiSigned, d), vpi_get(vpiScalar, d), vpi_get(vpiVector, d));
    bound("left", vpi_handle(vpiLeftRange, d));
    bound("right", vpi_handle(vpiRightRange, d));
    vpiHandle expr = vpi_handle(vpiExpr, d);
    if (!expr) {
      printf(" expr=null\n");
    } else if (vpi_get(vpiType, expr) == vpiRefObj) {
      printf(" expr=%s\n", vpi_get_str(vpiType, expr));
    } else {
      printf(" expr=%s", vpi_get_str(vpiFullName, expr));
      if (read)
        bound("value", expr);
      printf("\n");
    }
  }
}
void probe(void) {
  decls(vpi_handle_by_name("top.u", 0), 1);
  decls(vpi_handle_by_name("top.t", 0), 0);
}
