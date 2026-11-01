#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 store(PLI_BYTE8 *unused) {
  vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
  int put = vpi_put_userdata(call, "first");
  printf("first put=%d read=%s\n", put, (char *)vpi_get_userdata(call));
  put = vpi_put_userdata(call, "second");
  printf("second put=%d read=%s\n", put, (char *)vpi_get_userdata(call));
  printf("bad handle put=%d\n", vpi_put_userdata(NULL, "third"));
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$store", .calltf = store};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
