#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 show(PLI_BYTE8 *name) {
  printf("called %s\n", name);
  return 0;
}
static void add(PLI_BYTE8 *name) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = name, .calltf = show, .user_data = name};
  vpi_register_systf(&t);
}
static void start(void) {
  add("$my_task");
  add("$MY_TASK");
  add("$a1_b$c");
}
void (*vlog_startup_routines[])(void) = {start, 0};
