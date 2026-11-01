#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 killed(PLI_INT32 reason, p_vpi_time time, vpiHandle assertion, p_vpi_attempt_info info,
                        PLI_BYTE8 *user) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(NULL, &now);
  printf("%s kill ran=%u cb_time=%u\n", user, now.low, time->low);
  return 0;
}
void setup(void) {
  int registered = vpi_register_assertion_cb(vpi_handle_by_name("top.a1", 0), cbAssertionKill, killed, "a1") != 0;
  registered += vpi_register_assertion_cb(vpi_handle_by_name("top.a2", 0), cbAssertionKill, killed, "a2") != 0;
  printf("registered=%d\n", registered);
}
