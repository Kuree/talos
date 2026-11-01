#include "sv_vpi_user.h"
#include <stdio.h>
static s_cb_data caller;
static PLI_INT32 timed(p_cb_data cb) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(NULL, &now);
  // "this is not a pointer to the same structure that was passed to vpi_register_cb()"
  printf("%s now=%u time=%u user=%s new=%d\n", cb->reason == cbAfterDelay ? "cbAfterDelay" : "cbReadOnlySynch",
         now.low, cb->time ? cb->time->low : 0, cb->user_data, cb != &caller);
  return 0;
}
static PLI_INT32 ended(p_cb_data cb) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(NULL, &now);
  printf("%s now=%u user=%s new=%d\n", cb->reason == cbEndOfSimulation ? "cbEndOfSimulation" : "other", now.low,
         cb->user_data, cb != &caller);
  return 0;
}
void setup(void) {
  s_vpi_time delay = {.type = vpiSimTime, .low = 3};
  caller = (s_cb_data){.reason = cbAfterDelay, .cb_rtn = timed, .time = &delay, .user_data = "three"};
  vpiHandle handle = vpi_register_cb(&caller);
  printf("handle=%s\n", handle ? vpi_get_str(vpiType, handle) : "null");
  // A callback that is removed before its time never fires, or the next line in the log is wrong.
  delay.low = 5;
  caller.user_data = "removed";
  vpi_remove_cb(vpi_register_cb(&caller));
  delay.low = 7;
  caller.reason = cbReadOnlySynch;
  caller.user_data = "seven";
  vpi_register_cb(&caller);
  caller = (s_cb_data){.reason = cbEndOfSimulation, .cb_rtn = ended, .user_data = "end"};
  vpi_register_cb(&caller);
}
