#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 attempt(PLI_INT32 reason, p_vpi_time cb_time, vpiHandle assertion, p_vpi_attempt_info info, PLI_BYTE8 *data) {
  printf("success t=%d attempt start t=%d\n", cb_time->low, info->attemptStartTime.low);
  return 0;
}
void probe(void) {
  vpi_register_assertion_cb(vpi_handle_by_name("top.check", 0), cbAssertionSuccess, attempt, 0);
}
