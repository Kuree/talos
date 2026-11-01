#include "sv_vpi_user.h"
#include <stdio.h>
static void conn(const char *label, vpiHandle h) {
  if (h) {
    s_vpi_value v = {.format = vpiBinStrVal};
    vpi_get_value(h, &v);
    printf(" %s=%s", label, v.value.str);
  } else {
    printf(" %s=null", label);
  }
}
void show(int t) {
  vpiHandle it = vpi_iterate(vpiPort, vpi_handle_by_name("top.u", 0));
  for (vpiHandle p; it && (p = vpi_scan(it));) {
    int d = vpi_get(vpiDirection, p);
    // Detail 1: an ordinary port's vpiPortType is vpiPort.
    int type = vpi_get(vpiPortType, p);
    printf("t=%d port %d name=%s", t, vpi_get(vpiPortIndex, p), vpi_get_str(vpiName, p));
    printf(" dir=%s size=%d type=%s scalar=%d vector=%d explicit=%d",
           d == vpiInput ? "input" : d == vpiOutput ? "output" : "other", vpi_get(vpiSize, p),
           type == vpiPort ? "vpiPort" : "other", vpi_get(vpiScalar, p), vpi_get(vpiVector, p),
           vpi_get(vpiExplicitName, p));
    vpiHandle high = vpi_handle(vpiHighConn, p);
    if (high)
      printf(" byname=%d", vpi_get(vpiConnByName, p));
    conn("high", high);
    conn("low", vpi_handle(vpiLowConn, p));
    printf("\n");
  }
}
void bits(void) {
  vpiHandle port = vpi_scan(vpi_iterate(vpiPort, vpi_handle_by_name("top.u", 0)));
  vpiHandle it = vpi_iterate(vpiBit, port), last = 0;
  int n = 0;
  for (vpiHandle b; it && (b = vpi_scan(it)); n++)
    last = b;
  printf("port bits=%d", n);
  if (last) {
    printf(" type=%s", vpi_get_str(vpiType, last));
    printf(" parent=%s", vpi_get_str(vpiName, vpi_handle(vpiParent, last)));
  }
  printf("\n");
}
