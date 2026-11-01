#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static vpiHandle first(PLI_INT32 relation, vpiHandle h) {
  vpiHandle it = vpi_iterate(relation, h);
  return it ? vpi_scan(it) : 0;
}
void probe(void) {
  vpiHandle p, it = vpi_iterate(vpiModPath, vpi_handle_by_name("top.u", 0));
  if (!it) {
    printf("no module paths\n");
    return;
  }
  while ((p = vpi_scan(it))) {
    vpiHandle in = first(vpiModPathIn, p), out = first(vpiModPathOut, p), data = first(vpiModDataPathIn, p);
    int edge = in ? vpi_get(vpiEdge, in) : -1;
    printf("path type=%s", str(vpiType, p));
    printf(" parallel=%d full=%d", vpi_get(vpiPathType, p) == vpiPathParallel, vpi_get(vpiPathType, p) == vpiPathFull);
    printf(" in=%s", str(vpiName, in ? vpi_handle(vpiExpr, in) : 0));
    printf(" in_edge=%s", edge == vpiPosedge ? "pos" : edge == vpiNoEdge ? "none" : "other");
    printf(" out=%s", str(vpiName, out ? vpi_handle(vpiExpr, out) : 0));
    printf(" data=%s", str(vpiName, data ? vpi_handle(vpiExpr, data) : 0));
    printf(" positive=%d", vpi_get(vpiPolarity, p) == vpiPositive);
    printf(" condition=%s", str(vpiDecompile, vpi_handle(vpiCondition, p)));
    s_vpi_time t[2] = {{.type = vpiScaledRealTime}, {.type = vpiScaledRealTime}};
    s_vpi_delay d = {.da = t, .no_of_delays = 2, .time_type = vpiScaledRealTime};
    vpi_get_delays(p, &d);
    printf(" rise=%g fall=%g\n", t[0].real, t[1].real);
  }
}
