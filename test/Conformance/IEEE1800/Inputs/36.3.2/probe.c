#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 fixed(PLI_BYTE8 *data) {
  s_vpi_value v = {.format = vpiIntVal};
  v.value.integer = 42;
  vpi_put_value(vpi_handle(vpiSysTfCall, 0), &v, 0, vpiNoDelay);
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysFunc, .sysfunctype = vpiIntFunc, .tfname = "$random", .calltf = fixed};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
