#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static void skew(const char *label, PLI_INT32 relation, vpiHandle h) {
  vpiHandle dc = vpi_handle(relation, h);
  vpiHandle expr = dc ? vpi_handle(vpiDelay, dc) : 0;
  if (!expr) {
    printf(" %s=none", label);
    return;
  }
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(expr, &v);
  printf(" %s=%d", label, v.value.integer);
}
void probe(void) {
  vpiHandle top = vpi_handle_by_name("top", 0);
  vpiHandle it = vpi_iterate(vpiClockingBlock, top);
  vpiHandle cb = it ? vpi_scan(it) : 0;
  printf("block type=%s", str(vpiType, cb));
  printf(" name=%s\n", str(vpiName, cb));
  if (!cb)
    return;
  printf("full=%s\n", str(vpiFullName, cb));
  vpiHandle event = vpi_handle(vpiClockingEvent, cb);
  printf("event=%s\n", str(vpiDecompile, event ? vpi_handle(vpiCondition, event) : 0));
  printf("default");
  skew("input_skew", vpiInputSkew, cb);
  skew("output_skew", vpiOutputSkew, cb);
  printf(" input_edge_none=%d output_edge_none=%d\n", vpi_get(vpiInputEdge, cb) == vpiNoEdge,
         vpi_get(vpiOutputEdge, cb) == vpiNoEdge);
  printf("default_clocking=%s\n", str(vpiName, vpi_handle(vpiDefaultClocking, top)));
  vpiHandle io, ios = vpi_iterate(vpiClockingIODecl, cb);
  if (ios)
    while ((io = vpi_scan(ios))) {
      int dir = vpi_get(vpiDirection, io);
      printf("io %s input=%d output=%d", str(vpiName, io), dir == vpiInput, dir == vpiOutput);
      printf(" expr=%s", str(vpiName, vpi_handle(vpiExpr, io)));
      if (dir == vpiInput) {
        skew("input_skew", vpiInputSkew, io);
        printf(" input_neg=%d\n", vpi_get(vpiInputEdge, io) == vpiNegedge);
      } else {
        skew("output_skew", vpiOutputSkew, io);
        printf(" output_neg=%d\n", vpi_get(vpiOutputEdge, io) == vpiNegedge);
      }
    }
}
