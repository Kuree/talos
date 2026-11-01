#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
void probe(void) {
  vpiHandle f = vpi_handle(vpiFrame, NULL);
  if (!f)
    printf("no active frame\n");
  for (; f; f = vpi_handle(vpiParent, f)) {
    printf("frame type=%s active=%d", str(vpiType, f), vpi_get(vpiActive, f));
    printf(" origin=%s", str(vpiName, vpi_handle(vpiOrigin, f)));
    printf(" stmt=%s", str(vpiType, vpi_handle(vpiStmt, f)));
    printf(" thread=%s\n", str(vpiType, vpi_handle(vpiThread, f)));
    vpiHandle v, it = vpi_iterate(vpiAutomatics, f);
    if (it)
      while ((v = vpi_scan(it))) {
        s_vpi_value value = {.format = vpiIntVal};
        vpi_get_value(v, &value);
        printf("local %s=%d\n", str(vpiName, v), value.value.integer);
      }
  }
}
