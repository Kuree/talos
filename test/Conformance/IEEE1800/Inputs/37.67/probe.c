#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void stmt_of(const char *label, int relation, vpiHandle s) {
  vpiHandle t = vpi_handle(relation, s);
  printf(" %s=%s", label, t ? vpi_get_str(vpiType, t) : "null");
}

static void show_wait(vpiHandle s) {
  vpiHandle c = vpi_handle(vpiCondition, s);
  printf("%s", vpi_get_str(vpiType, s));
  printf(" condition=%s", c ? vpi_get_str(vpiName, c) : "null");
  if (c)
    printf("=%d", value(c));
  stmt_of("stmt", vpiStmt, s);
  printf("\n");
}

static void show_ordered(vpiHandle s) {
  vpiHandle it = vpi_iterate(vpiCondition, s), c;
  printf("%s conditions=", vpi_get_str(vpiType, s));
  while (it && (c = vpi_scan(it)))
    printf("%s,", vpi_get_str(vpiName, c));
  stmt_of("stmt", vpiStmt, s);
  stmt_of("else", vpiElseStmt, s);
  printf("\n");
}

void probe(void) {
  vpiHandle procs = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  while ((p = vpi_scan(procs))) {
    vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
    while (it && (s = vpi_scan(it)))
      switch (vpi_get(vpiType, s)) {
      case vpiWait: show_wait(s); break;
      case vpiOrderedWait: show_ordered(s); break;
      case vpiWaitFork:
        printf("%s", vpi_get_str(vpiType, s));
        stmt_of("stmt", vpiStmt, s);
        printf("\n");
        break;
      }
  }
}
