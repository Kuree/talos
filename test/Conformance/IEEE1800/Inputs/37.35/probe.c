#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static const char *bin(vpiHandle h) {
  s_vpi_value v = {.format = vpiBinStrVal};
  vpi_get_value(h, &v);
  return v.value.str ? v.value.str : "null";
}
static vpiHandle gate(void) {
  vpiHandle it = vpi_iterate(vpiPrimitive, vpi_handle_by_name("top", 0));
  return it ? vpi_scan(it) : 0;
}
void describe(void) {
  vpiHandle g = gate();
  printf("type=%s", str(vpiType, g));
  printf(" name=%s\n", str(vpiName, g));
  printf("full=%s\n", str(vpiFullName, g));
  printf("def=%s", str(vpiDefName, g));
  printf(" is_nand=%d inputs=%d strong0=%d pull1=%d\n", vpi_get(vpiPrimType, g) == vpiNandPrim, vpi_get(vpiSize, g),
         vpi_get(vpiStrength0, g) == vpiStrongDrive, vpi_get(vpiStrength1, g) == vpiPullDrive);
  s_vpi_time t[2] = {{.type = vpiScaledRealTime}, {.type = vpiScaledRealTime}};
  s_vpi_delay d = {.da = t, .no_of_delays = 2, .time_type = vpiScaledRealTime};
  vpi_get_delays(g, &d);
  printf("delay rise=%g fall=%g\n", t[0].real, t[1].real);
}
void terms(void) {
  vpiHandle g = gate(), term, it = vpi_iterate(vpiPrimTerm, g);
  if (it)
    while ((term = vpi_scan(it))) {
      printf("term index=%d output=%d", vpi_get(vpiTermIndex, term), vpi_get(vpiDirection, term) == vpiOutput);
      printf(" value=%s\n", bin(term));
    }
  printf("primitive value=%s\n", bin(g));
}
