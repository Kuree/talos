#include "vpi_user.h"
static int calls;
static PLI_INT32 changed(p_cb_data cb) { ++calls; return 0; }
int register_change(void) {
  static s_vpi_time time={.type=vpiSuppressTime};
  static s_vpi_value value={.format=vpiSuppressVal};
  s_cb_data cb={.reason=cbValueChange,.cb_rtn=changed,
    .obj=vpi_handle_by_name((PLI_BYTE8 *)"top.value",0),
    .time=&time,.value=&value};
  return cb.obj && vpi_register_cb(&cb)!=0;
}
int change_count(void) { return calls; }
