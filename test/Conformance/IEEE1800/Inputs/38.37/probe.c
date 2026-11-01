#include "sv_vpi_user.h"
#include <stdio.h>
static vpiHandle registered;
static int calls;
static PLI_INT32 hello(PLI_BYTE8 *user) {
  printf("calltf %d user=%s\n", ++calls, user);
  return 0;
}
static void start(void) {
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$hello", .calltf = hello, .user_data = "tag"};
  registered = vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {start, 0};
void handle_type(void) { printf("handle=%s\n", registered ? vpi_get_str(vpiType, registered) : "null"); }
