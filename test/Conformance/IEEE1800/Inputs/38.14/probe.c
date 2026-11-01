#include "sv_vpi_user.h"
#include <stdint.h>
#include <stdio.h>
static PLI_INT32 tally(PLI_BYTE8 *unused) {
  vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
  s_vpi_value site = {.format = vpiIntVal};
  vpi_get_value(vpi_scan(vpi_iterate(vpiArgument, call)), &site);
  // Each call site has its own storage, which keeps its value between invocations.
  intptr_t count = (intptr_t)vpi_get_userdata(call);
  printf("site %d data=%s count=%d\n", site.value.integer, count ? "stored" : "none", (int)count + 1);
  vpi_put_userdata(call, (void *)(count + 1));
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$tally", .calltf = tally};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
