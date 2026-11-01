#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 fired(p_cb_data cb) { return 0; }
static const char *severity(int level) {
  switch (level) {
  case 0: return "0";
  case vpiNotice: return "vpiNotice";
  case vpiWarning: return "vpiWarning";
  case vpiError: return "vpiError";
  case vpiSystem: return "vpiSystem";
  case vpiInternal: return "vpiInternal";
  }
  return "unknown";
}
void probe(void) {
  // 38.36.2: a NULL time field on a simulation time callback "will result in an error".
  s_cb_data bad = {.reason = cbAfterDelay, .cb_rtn = fired};
  vpiHandle handle = vpi_register_cb(&bad);
  s_vpi_error_info info = {0};
  printf("failed: handle=%s level=%s\n", handle ? "live" : "null", severity(vpi_chk_error(&info)));
  printf("info: level=%s state=%d message=%d\n", severity(info.level),
         info.state == vpiCompile || info.state == vpiPLI || info.state == vpiRun,
         info.message && info.message[0]);
  // Checking has no effect on the status, and the argument can be NULL.
  printf("still: level=%s\n", severity(vpi_chk_error(NULL)));
  // Any other VPI routine resets it.
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(vpi_handle_by_name("top.n", 0), &value);
  printf("clean: n=%d level=%s\n", value.value.integer, severity(vpi_chk_error(NULL)));
}
