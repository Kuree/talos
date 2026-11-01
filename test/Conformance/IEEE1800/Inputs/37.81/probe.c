#include "sv_vpi_user.h"
#include <stdio.h>

static void list(const char *where) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(NULL, &now);
  vpiHandle it = vpi_iterate(vpiTimeQueue, NULL), q;
  printf("%s at %u:", where, now.low);
  if (!it)
    printf(" null");
  while (it && (q = vpi_scan(it))) {
    s_vpi_time t = {.type = vpiSimTime};
    vpi_get_time(q, &t);
    printf(" %s", vpi_get_str(vpiType, q));
    printf("=%u,", t.low);
  }
  printf("\n");
}

static PLI_INT32 read_only_sync(p_cb_data data) {
  list("read-only sync");
  return 0;
}

void list_now(void) { list("NBA pending"); }

void list_at_read_only_sync(void) {
  s_vpi_time delay = {.type = vpiSimTime};
  s_cb_data cb = {.reason = cbReadOnlySynch, .cb_rtn = read_only_sync, .time = &delay};
  vpi_register_cb(&cb);
}
