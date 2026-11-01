#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 stamp(PLI_BYTE8 *data) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(0, &now);
  printf("calltf time=%d\n", now.low);
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$stamp", .calltf = stamp};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
