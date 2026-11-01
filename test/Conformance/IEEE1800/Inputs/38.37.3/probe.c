#include "sv_vpi_user.h"
#include <stdio.h>
static int task_calls, int_calls, sized_calls;
static void give(int value) {
  s_vpi_value v = {.format = vpiIntVal, .value.integer = value};
  vpi_put_value(vpi_handle(vpiSysTfCall, NULL), &v, NULL, vpiNoDelay);
}
static PLI_INT32 my_task(PLI_BYTE8 *u) {
  printf("my_task %d\n", ++task_calls);
  return 0;
}
static PLI_INT32 my_int_func(PLI_BYTE8 *u) {
  int_calls++;
  give(41);
  return 0;
}
static PLI_INT32 my_sized_func(PLI_BYTE8 *u) {
  sized_calls++;
  give(170);
  return 0;
}
static PLI_INT32 my_sized_size(PLI_BYTE8 *u) { return 8; }
static void register_my_systfs(void) {
  static s_vpi_systf_data list[] = {
      {vpiSysTask, 0, "$my_task", my_task, 0, 0, 0},
      {vpiSysFunc, vpiIntFunc, "$my_int_func", my_int_func, 0, 0, 0},
      {vpiSysFunc, vpiSizedFunc, "$my_sized_func", my_sized_func, 0, my_sized_size, 0},
      {0},
  };
  for (p_vpi_systf_data p = list; p->type; p++)
    vpi_register_systf(p);
}
void (*vlog_startup_routines[])(void) = {register_my_systfs, 0};
void report(void) { printf("int calls=%d sized calls=%d\n", int_calls, sized_calls); }
