#include "vpi_user.h"
static int calls;
static PLI_INT32 fired(p_cb_data cb) { ++calls; return 0; }
int register_and_remove(void) {
  static s_vpi_time delay={.type=vpiSimTime,.low=2};
  s_cb_data cb={.reason=cbAfterDelay,.cb_rtn=fired,.time=&delay};
  vpiHandle h=vpi_register_cb(&cb);
  return h && vpi_remove_cb(h)==1;
}
int callback_count(void) { return calls; }
