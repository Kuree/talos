#include "sv_vpi_user.h"
#include <stdio.h>
static vpiHandle port(const char *instance, int relation) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiPort, vpi_handle_by_name((PLI_BYTE8 *)instance, 0)));
  return p ? vpi_handle(relation, p) : 0;
}
static void head(const char *label, vpiHandle h) {
  printf("%s type=%s", label, h ? vpi_get_str(vpiType, h) : "null");
}
static void named(vpiHandle h) {
  printf(" name=%s", vpi_get_str(vpiName, h));
  printf(" generic=%d", vpi_get(vpiGeneric, h));
}
static void actual(vpiHandle h, const char *key, int property) {
  vpiHandle a = h ? vpi_handle(vpiActual, h) : 0;
  if (!a) {
    printf(" %s=null", key);
    return;
  }
  printf(" %s=%s", key, vpi_get_str(property, a));
  printf(" actual-type=%s", vpi_get_str(vpiType, a));
}
void probe(void) {
  vpiHandle low = port("top.u1", vpiLowConn);
  head("ref port low", low);
  printf(" name=%s", vpi_get_str(vpiName, low));
  printf(" full=%s", vpi_get_str(vpiFullName, low));
  printf(" generic=%d", vpi_get(vpiGeneric, low));
  actual(low, "actual", vpiFullName);
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(vpi_handle(vpiActual, low), &v);
  printf(" actual-value=%d\n", v.value.integer);
  vpiHandle type = vpi_handle(vpiTypespec, low);
  printf("typespec=%s\n", type ? vpi_get_str(vpiType, type) : "null");
  low = port("top.i1", vpiLowConn);
  head("interface port low", low);
  named(low);
  printf(" def=%s", vpi_get_str(vpiDefName, low));
  actual(low, "actual", vpiFullName);
  printf("\n");
  vpiHandle high = port("top.i1", vpiHighConn);
  head("interface port high", high);
  actual(high, "actual", vpiFullName);
  printf("\n");
  high = port("top.i2", vpiHighConn);
  head("modport high", high);
  actual(high, "actual-name", vpiName);
  printf("\n");
  low = port("top.i2", vpiLowConn);
  head("modport low", low);
  named(low);
  printf(" def=%s", vpi_get_str(vpiDefName, low));
  actual(low, "actual-name", vpiName);
  printf("\n");
  low = port("top.i3", vpiLowConn);
  head("generic low", low);
  printf(" generic=%d\n", vpi_get(vpiGeneric, low));
  vpiHandle decl = vpi_scan(vpi_iterate(vpiIODecl, vpi_handle_by_name("top.t", 0)));
  vpiHandle formal = decl ? vpi_handle(vpiExpr, decl) : 0;
  head("task formal", formal);
  printf(" name=%s\n", formal ? vpi_get_str(vpiName, formal) : "null");
}
