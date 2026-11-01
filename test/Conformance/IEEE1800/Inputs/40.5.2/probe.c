#include "sv_vpi_user.h"
#include <stdio.h>
static void assertion(const char *name) {
  char full[32];
  snprintf(full, sizeof full, "top.%s", name);
  vpiHandle a = vpi_handle_by_name(full, 0);
  printf("%s covered=%d attempt=%d success=%d failure=%d\n", name, vpi_get(vpiCovered, a),
         vpi_get(vpiAssertAttemptCovered, a) > 0, vpi_get(vpiAssertSuccessCovered, a) > 0,
         vpi_get(vpiAssertFailureCovered, a) > 0);
}
void probe(void) {
  vpiHandle top = vpi_handle_by_name("top", 0), s = vpi_handle_by_name("top.s", 0);
  printf("signal covered=%d max=%d\n", vpi_get(vpiCovered, s), vpi_get(vpiCoveredMax, s));
  printf("instance toggle=%d\n", vpi_get(vpiToggleCoverage, top) > 0);
  assertion("aundf");
  assertion("afail");
  assertion("apass");
  printf("max=%d\n", vpi_get(vpiCoveredMax, vpi_handle_by_name("top.apass", 0)));
  vpiHandle fsms = vpi_iterate(vpiFsm, top);
  vpiHandle fsm = fsms ? vpi_scan(fsms) : 0;
  if (!fsm) {
    printf("fsm null\n");
    return;
  }
  int states = 0;
  vpiHandle it = vpi_iterate(vpiFsmStates, fsm);
  while (it && vpi_scan(it))
    states++;
  printf("fsm covered=%d max=%d states=%d\n", vpi_get(vpiCovered, fsm), vpi_get(vpiCoveredMax, fsm), states);
  printf("fsm expression=%s\n", vpi_get_str(vpiFullName, vpi_handle(vpiFsmStateExpression, fsm)));
}
