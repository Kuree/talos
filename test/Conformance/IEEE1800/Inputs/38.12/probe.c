#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 task_call(PLI_BYTE8 *u) { return 0; }
static PLI_INT32 task_compile(PLI_BYTE8 *u) { return 0; }
static PLI_INT32 func_call(PLI_BYTE8 *u) { return 0; }
static PLI_INT32 func_size(PLI_BYTE8 *u) { return 8; }
static vpiHandle task, func;
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$probe_task", .calltf = task_call,
                        .compiletf = task_compile, .user_data = "task data"};
  s_vpi_systf_data f = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$probe_func",
                        .calltf = func_call, .sizetf = func_size, .user_data = "func data"};
  task = vpi_register_systf(&t);
  func = vpi_register_systf(&f);
}
void (*vlog_startup_routines[])(void) = {start, 0};
void probe(void) {
  s_vpi_systf_data i = {0};
  vpi_get_systf_info(task, &i);
  printf("%s task=%d functype=%d calltf=%d compiletf=%d sizetf=%d user=%s\n", i.tfname ? i.tfname : "null",
         i.type == vpiSysTask, i.sysfunctype, i.calltf == task_call, i.compiletf == task_compile,
         i.sizetf == NULL, i.user_data ? i.user_data : "null");
  vpi_get_systf_info(func, &i);
  printf("%s func=%d functype=%s calltf=%d compiletf=%d sizetf=%d user=%s\n", i.tfname ? i.tfname : "null",
         i.type == vpiSysFunc, i.sysfunctype == vpiSizedFunc ? "sized" : "other", i.calltf == func_call,
         i.compiletf == NULL, i.sizetf == func_size, i.user_data ? i.user_data : "null");
}
