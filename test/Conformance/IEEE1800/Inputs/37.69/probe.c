#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

void probe(long long now) {
  vpiHandle p = NULL, it = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0));
  while ((p = vpi_scan(it)))
    if (vpi_get(vpiType, vpi_handle(vpiStmt, p)) == vpiBegin)
      break;
  vpiHandle s = vpi_scan(vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)));
  vpiHandle control = vpi_handle(vpiRepeatControl, s);
  printf("control=%s", control ? vpi_get_str(vpiType, control) : "null");
  if (control) {
    vpiHandle count = vpi_handle(vpiExpr, control), event = vpi_handle(vpiEventControl, control);
    if (count)
      printf(" count=%d", value(count));
    else
      printf(" count=null");
    printf(" event=%s", event ? vpi_get_str(vpiType, event) : "null");
    if (event) {
      vpiHandle c = vpi_handle(vpiCondition, event);
      printf(" condition=%s", c ? vpi_get_str(vpiName, c) : "null");
    }
  }
  printf(" n=%d at %lld\n", value(vpi_handle(vpiLhs, s)), now);
}
