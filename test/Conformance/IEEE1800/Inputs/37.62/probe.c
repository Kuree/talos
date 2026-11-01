#include "sv_vpi_user.h"
#include <stdio.h>

/* The body of the only process of top that is a begin block. */
static vpiHandle block(void) {
  vpiHandle it = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)), p;
  while ((p = vpi_scan(it))) {
    vpiHandle s = vpi_handle(vpiStmt, p);
    if (s && vpi_get(vpiType, s) == vpiBegin)
      return s;
  }
  return NULL;
}

static void show(vpiHandle s) {
  vpiHandle event = vpi_handle(vpiNamedEvent, s);
  printf("%s", vpi_get_str(vpiType, s));
  printf(" blocking=%d event=%s\n", vpi_get(vpiBlocking, s), event ? vpi_get_str(vpiName, event) : "null");
}

void probe(void) {
  /* #1 -> go wraps its statement in a delay control; ->> later stands alone. */
  vpiHandle it = vpi_iterate(vpiStmt, block()), s;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type == vpiDelayControl) {
      vpiHandle body = vpi_handle(vpiStmt, s);
      if (body && vpi_get(vpiType, body) == vpiEventStmt)
        show(body);
    } else if (type == vpiEventStmt)
      show(s);
  }
}
