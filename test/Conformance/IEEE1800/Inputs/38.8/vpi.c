#include "vpi_user.h"
static PLI_INT32 fired(p_cb_data cb) { return 0; }
int probe(void) {
  static s_vpi_time delay={.type=vpiSimTime,.low=2};
  s_cb_data expected={.reason=cbAfterDelay,.cb_rtn=fired,.time=&delay,
    .user_data=(PLI_BYTE8 *)"tag"};
  vpiHandle h=vpi_register_cb(&expected);
  if(!h)return 0;
  s_cb_data actual={0};
  vpi_get_cb_info(h,&actual);
  return actual.reason==expected.reason && actual.cb_rtn==fired &&
    actual.user_data==expected.user_data;
}
