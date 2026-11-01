#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static const char *bin(vpiHandle h) {
  s_vpi_value v = {.format = vpiBinStrVal};
  if (!h)
    return "null";
  vpi_get_value(h, &v);
  return v.value.str ? v.value.str : "null";
}
static vpiHandle first(PLI_INT32 relation, vpiHandle h) {
  vpiHandle it = h ? vpi_iterate(relation, h) : 0;
  return it ? vpi_scan(it) : 0;
}
static vpiHandle device(void) { return first(vpiDelayDevice, vpi_handle_by_name("top.u", 0)); }
void describe(void) {
  vpiHandle d = device();
  printf("device=%s modpath=%d\n", str(vpiType, d), d && vpi_get(vpiDelayType, d) == vpiModPathDelay);
  vpiHandle in = first(vpiInTerm, d), out = first(vpiOutTerm, d);
  printf("in=%s modpath=%d\n", str(vpiType, in), in && vpi_get(vpiDelayType, in) == vpiModPathDelay);
  printf("out=%s modpath=%d\n", str(vpiType, out), out && vpi_get(vpiDelayType, out) == vpiModPathDelay);
}
void values(int t) {
  vpiHandle d = device();
  printf("t=%d in=%s", t, bin(first(vpiInTerm, d)));
  printf(" out=%s\n", bin(first(vpiOutTerm, d)));
}
