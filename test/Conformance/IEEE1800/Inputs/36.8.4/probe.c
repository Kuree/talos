#include "sv_vpi_user.h"
#include <stdio.h>
static const int tag = 165;
static PLI_INT32 size(PLI_BYTE8 *data) {
  printf("sizetf user_data=%d\n", *(const int *)data);
  return 8;
}
static PLI_INT32 compile_check(PLI_BYTE8 *data) {
  printf("compiletf user_data=%d\n", *(const int *)data);
  return 0;
}
static PLI_INT32 call(PLI_BYTE8 *data) {
  printf("calltf user_data=%d\n", *(const int *)data);
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$tagged", .sizetf = size,
                        .compiletf = compile_check, .calltf = call, .user_data = (PLI_BYTE8 *)&tag};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
