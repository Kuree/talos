#include "sv_vpi_user.h"
#include <stdio.h>
static int compiled;
static int argument(vpiHandle arguments) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(vpi_scan(arguments), &v);
  return v.value.integer;
}
static PLI_INT32 sum_compile(PLI_BYTE8 *user) {
  compiled = 1;
  return 0;
}
static PLI_INT32 sum_size(PLI_BYTE8 *user) { return 8; }
static PLI_INT32 sum_call(PLI_BYTE8 *user) {
  vpiHandle call = vpi_handle(vpiSysTfCall, NULL), arguments = vpi_iterate(vpiArgument, call);
  int sum = argument(arguments);
  sum += argument(arguments);
  printf("calltf user=%s compiled=%d sum=%d\n", user, compiled, sum);
  s_vpi_value result = {.format = vpiIntVal, .value.integer = sum};
  vpi_put_value(call, &result, NULL, vpiNoDelay);
  return 0;
}
static PLI_INT32 unsized_call(PLI_BYTE8 *user) {
  s_vpi_value result = {.format = vpiIntVal, .value.integer = 1};
  vpi_put_value(vpi_handle(vpiSysTfCall, NULL), &result, NULL, vpiNoDelay);
  return 0;
}
static PLI_INT32 count_call(PLI_BYTE8 *user) {
  int count = 0;
  vpiHandle arguments = vpi_iterate(vpiArgument, vpi_handle(vpiSysTfCall, NULL));
  while (arguments && vpi_scan(arguments))
    count++;
  printf("task args=%d\n", count);
  return 0;
}
static void start(void) {
  s_vpi_systf_data f = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$sum8", .calltf = sum_call,
                        .compiletf = sum_compile, .sizetf = sum_size, .user_data = "func"};
  vpi_register_systf(&f);
  s_vpi_systf_data u = {.type = vpiSysFunc, .sysfunctype = vpiSizedFunc, .tfname = "$unsized", .calltf = unsized_call};
  vpi_register_systf(&u);
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$count_args", .calltf = count_call};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
