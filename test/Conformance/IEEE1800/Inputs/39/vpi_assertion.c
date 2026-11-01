#include "sv_vpi_user.h"
static PLI_INT32 succeeded(PLI_INT32 reason,p_vpi_time time,vpiHandle assertion,p_vpi_attempt_info info,PLI_BYTE8 *user) { return 0; }
int probe_assertion_api(void) {
  vpiHandle assertion=vpi_handle_by_name((PLI_BYTE8*)"top.p",0);
  if(!assertion) return -1;
  return vpi_register_assertion_cb(assertion,cbAssertionSuccess,succeeded,0)?1:-2;
}
