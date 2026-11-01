#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static const char *full(vpiHandle h) { return h ? vpi_get_str(vpiFullName, h) : "null"; }
void describe(void) {
  vpiHandle v = vpi_handle_by_name("top.v", 0);
  printf("v type=%s", vpi_get_str(vpiType, v));
  printf(" name=%s", vpi_get_str(vpiName, v));
  printf(" full=%s", vpi_get_str(vpiFullName, v));
  printf(" modport=%d", vpi_get(vpiIsModPort, v));
  vpiHandle type = vpi_handle(vpiTypespec, v);
  printf(" typespec=%s", vpi_get_str(vpiType, type));
  printf(" def=%s", vpi_get_str(vpiDefName, type));
  // Details 1 and 37.29's example: vpiActual is NULL while the variable is uninitialized.
  printf(" actual=%s", full(vpi_handle(vpiActual, v)));
  printf(" expr=%s\n", full(vpi_handle(vpiExpr, v)));
}
void actual(void) {
  vpiHandle a = vpi_handle(vpiActual, vpi_handle_by_name("top.v", 0));
  printf("v actual=%s", full(a));
  printf(" type=%s\n", a ? vpi_get_str(vpiType, a) : "null");
}
void rest(void) {
  vpiHandle init = vpi_handle_by_name("top.init", 0);
  printf("init actual=%s", full(vpi_handle(vpiActual, init)));
  printf(" expr=%s\n", full(vpi_handle(vpiExpr, init)));
  vpiHandle vm = vpi_handle_by_name("top.vm", 0);
  vpiHandle a = vpi_handle(vpiActual, vm);
  printf("vm modport=%d", vpi_get(vpiIsModPort, vm));
  printf(" def=%s", vpi_get_str(vpiDefName, vpi_handle(vpiTypespec, vm)));
  printf(" actual=%s", a ? vpi_get_str(vpiName, a) : "null");
  printf(" type=%s\n", a ? vpi_get_str(vpiType, a) : "null");
  // 37.12 detail 7: vpiVirtualInterfaceVar returns each element, vpiVariables the array once.
  vpiHandle top = vpi_handle_by_name("top", 0);
  int vifs = 0;
  vpiHandle it = vpi_iterate(vpiVirtualInterfaceVar, top);
  while (it && vpi_scan(it))
    vifs++;
  const char *array = "null";
  it = vpi_iterate(vpiVariables, top);
  for (vpiHandle h; it && (h = vpi_scan(it));)
    if (!strcmp(vpi_get_str(vpiName, h), "va"))
      array = vpi_get(vpiType, h) == vpiArrayVar ? "vpiArrayVar" : "other";
  printf("vifs=%d variables array=%s\n", vifs, array);
}
