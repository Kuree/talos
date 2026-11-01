#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 ignored(p_cb_data data) { return 0; }
static PLI_INT32 compiled(p_cb_data data) {
  printf("end of compile lookup=%d\n", vpi_handle_by_name("top.n", 0) != 0);
  return 0;
}
static void allow(const char *name, int reason, PLI_INT32 (*routine)(p_cb_data)) {
  s_cb_data cb = {.reason = reason, .cb_rtn = routine};
  printf("%s=%d\n", name, vpi_register_cb(&cb) != 0);
}
static void start(void) {
  printf("startup lookup=%d\n", vpi_handle_by_name("top.n", 0) != 0);
  allow("cbEndOfCompile", cbEndOfCompile, compiled);
  allow("cbStartOfSimulation", cbStartOfSimulation, ignored);
  allow("cbEndOfSimulation", cbEndOfSimulation, ignored);
  allow("cbUnresolvedSystf", cbUnresolvedSystf, ignored);
  allow("cbError", cbError, ignored);
  allow("cbPLIError", cbPLIError, ignored);
}
void (*vlog_startup_routines[])(void) = {start, 0};
