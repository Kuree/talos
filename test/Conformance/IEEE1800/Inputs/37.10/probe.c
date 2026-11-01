#include "sv_vpi_user.h"
#include <stdio.h>
static void instance(const char *label, const char *path) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
  printf("%s type=%s", label, vpi_get_str(vpiType, h));
  printf(" def=%s", vpi_get_str(vpiDefName, h));
  printf(" vpiTop=%d auto=%d unit=%d precision=%d\n", vpi_get(vpiTop, h), vpi_get(vpiAutomatic, h),
         vpi_get(vpiTimeUnit, h), vpi_get(vpiTimePrecision, h));
}
static const char *full(vpiHandle h) { return h ? vpi_get_str(vpiFullName, h) : "null"; }
static void owner(const char *label, const char *path) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
  printf("%s instance=%s", label, full(vpi_handle(vpiInstance, h)));
  printf(" module=%s\n", full(vpi_handle(vpiModule, h)));
}
void probe(void) {
  instance("top", "top");
  instance("u", "top.u");
  // Details 2 and 3: vpiInstance is the immediate instance; vpiModule is NULL outside a module.
  owner("var in module", "top.u.s");
  owner("var in program", "top.p.pr");
  // Detail 5: a package's full name ends in "::" and its members start with that prefix.
  vpiHandle it = vpi_iterate(vpiPackage, 0);
  vpiHandle package = it ? vpi_scan(it) : 0;
  if (package) {
    printf("package type=%s", vpi_get_str(vpiType, package));
    printf(" full=%s unit=%d\n", vpi_get_str(vpiFullName, package), vpi_get(vpiUnit, package));
  }
  vpiHandle pv = vpi_handle_by_name("pkg::pv", 0);
  if (pv) {
    s_vpi_value v = {.format = vpiIntVal};
    vpi_get_value(pv, &v);
    printf("var in package full=%s value=%d", vpi_get_str(vpiFullName, pv), v.value.integer);
    printf(" instance=%s\n", full(vpi_handle(vpiInstance, pv)));
  }
  // Detail 7: NULL asks for the smallest precision in the design.
  printf("smallest precision=%d\n", vpi_get(vpiTimePrecision, 0));
}
