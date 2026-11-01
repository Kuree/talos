#include "vpi_user.h"
static int calls;
static PLI_INT32 fired(p_cb_data cb) { ++calls; return 0; }
int register_after(void) {
  static s_vpi_time delay={.type=vpiSimTime,.low=2};
  s_cb_data cb={.reason=cbAfterDelay,.cb_rtn=fired,.time=&delay};
  return vpi_register_cb(&cb)!=0;
}
int callback_count(void) { return calls; }
