#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

/* The variable an assignment statement writes, with its current value. */
static void show_lhs(const char *label, vpiHandle s) {
  vpiHandle lhs = s ? vpi_handle(vpiLhs, s) : NULL;
  printf(" %s=%s", label, lhs ? vpi_get_str(vpiName, lhs) : "null");
  if (lhs)
    printf("=%d", value(lhs));
}

void probe(void) {
  vpiHandle procs = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  while ((p = vpi_scan(procs))) {
    vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
    while (it && (s = vpi_scan(it))) {
      if (vpi_get(vpiType, s) != vpiExpectStmt)
        continue;
      vpiHandle spec = vpi_handle(vpiPropertySpec, s);
      printf("%s", vpi_get_str(vpiType, s));
      printf(" property=%s", spec ? vpi_get_str(vpiType, spec) : "null");
      show_lhs("stmt", vpi_handle(vpiStmt, s));
      show_lhs("else", vpi_handle(vpiElseStmt, s));
      printf("\n");
    }
  }
}
