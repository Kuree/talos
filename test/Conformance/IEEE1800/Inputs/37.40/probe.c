#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static const char *edge(vpiHandle term) {
  int e = term ? vpi_get(vpiEdge, term) : -1;
  return e == vpiPosedge ? "pos" : e == vpiNoEdge ? "none" : "other";
}
void probe(void) {
  vpiHandle t, it = vpi_iterate(vpiTchk, vpi_handle_by_name("top.u", 0));
  if (!it) {
    printf("no timing checks\n");
    return;
  }
  vpiHandle setup = 0;
  while ((t = vpi_scan(it))) {
    vpiHandle ref = vpi_handle(vpiTchkRefTerm, t), data = vpi_handle(vpiTchkDataTerm, t);
    int kind = vpi_get(vpiTchkType, t);
    if (kind == vpiSetup)
      setup = t;
    printf("tchk type=%s", str(vpiType, t));
    printf(" setup=%d hold=%d", kind == vpiSetup, kind == vpiHold);
    printf(" ref=%s", str(vpiName, ref ? vpi_handle(vpiExpr, ref) : 0));
    printf(" ref_edge=%s", edge(ref));
    printf(" data=%s", str(vpiName, data ? vpi_handle(vpiExpr, data) : 0));
    printf(" data_edge=%s", edge(data));
    printf(" data_cond=%s", str(vpiDecompile, data ? vpi_handle(vpiCondition, data) : 0));
    s_vpi_time limit = {.type = vpiScaledRealTime};
    s_vpi_delay d = {.da = &limit, .no_of_delays = 1, .time_type = vpiScaledRealTime};
    vpi_get_delays(t, &d);
    printf(" limit=%g", limit.real);
    printf(" notifier=%s\n", str(vpiName, vpi_handle(vpiTchkNotifier, t)));
  }
  vpiHandle a, args = setup ? vpi_iterate(vpiExpr, setup) : 0;
  if (args)
    while ((a = vpi_scan(args)))
      printf("arg %s\n", str(vpiType, a));
}
