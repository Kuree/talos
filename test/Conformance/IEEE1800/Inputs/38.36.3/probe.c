#include "sv_vpi_user.h"
#include <stdio.h>
static const char *reason(int r) {
  switch (r) {
  case cbEndOfCompile: return "cbEndOfCompile";
  case cbStartOfSimulation: return "cbStartOfSimulation";
  case cbEndOfSimulation: return "cbEndOfSimulation";
  case cbPLIError: return "cbPLIError";
  }
  return "other";
}
static PLI_INT32 action(p_cb_data cb) {
  printf("%s user=%s\n", reason(cb->reason), cb->user_data);
  return 0;
}
static PLI_INT32 error(p_cb_data cb) {
  printf("%s user=%s level=%d\n", reason(cb->reason), cb->user_data, vpi_chk_error(NULL) != 0);
  return 0;
}
static PLI_INT32 compiled(p_cb_data cb) {
  action(cb);
  // Registered here, not in the startup table, which may only register what the tool supports.
  s_cb_data pli = {.reason = cbPLIError, .cb_rtn = error, .user_data = "error"};
  printf("cbPLIError registered=%d\n", vpi_register_cb(&pli) != 0);
  return 0;
}
static void start(void) {
  s_cb_data cb = {.reason = cbEndOfCompile, .cb_rtn = compiled, .user_data = "compile"};
  vpi_register_cb(&cb);
  cb = (s_cb_data){.reason = cbStartOfSimulation, .cb_rtn = action, .user_data = "start"};
  vpi_register_cb(&cb);
  cb = (s_cb_data){.reason = cbEndOfSimulation, .cb_rtn = action, .user_data = "end"};
  vpi_register_cb(&cb);
}
void (*vlog_startup_routines[])(void) = {start, 0};
void fail(void) {
  // 38.36.2: a NULL time field on a simulation time callback "will result in an error".
  s_cb_data bad = {.reason = cbAfterDelay, .cb_rtn = action};
  vpi_register_cb(&bad);
}
