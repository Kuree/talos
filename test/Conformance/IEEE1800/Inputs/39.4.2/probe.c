#include "sv_vpi_user.h"
#include <stdio.h>
static vpiHandle handles[3];
static PLI_INT32 on_event(PLI_INT32 reason, p_vpi_time time, vpiHandle assertion, p_vpi_attempt_info info,
                          PLI_BYTE8 *user) {
  const char *name = reason == cbAssertionStart ? "start" : reason == cbAssertionSuccess ? "success" : "failure";
  printf("%s time=%u attempt=%u", name, time->low, info->attemptStartTime.low);
  printf(" name=%s user=%s", vpi_get_str(vpiName, assertion), user);
  if (reason == cbAssertionFailure)
    printf(" fail_expr=%d", info->detail.failExpr != NULL);
  printf("\n");
  return 0;
}
void setup(void) {
  vpiHandle a1 = vpi_handle_by_name("top.a1", 0);
  handles[0] = vpi_register_assertion_cb(a1, cbAssertionStart, on_event, "tag");
  handles[1] = vpi_register_assertion_cb(a1, cbAssertionSuccess, on_event, "tag");
  handles[2] = vpi_register_assertion_cb(a1, cbAssertionFailure, on_event, "tag");
  printf("registered=%d\n", (handles[0] != 0) + (handles[1] != 0) + (handles[2] != 0));
}
void drop(void) {
  int removed = 1;
  for (int i = 0; i < 3; i++)
    removed &= vpi_remove_cb(handles[i]);
  printf("removed=%d\n", removed);
}
