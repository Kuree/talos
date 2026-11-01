#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT32 call(PLI_BYTE8 *user) {
  printf("calltf %s\n", user);
  return 0;
}
static void first(void) {
  printf("startup first\n");
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$one", .calltf = call, .user_data = "one"};
  vpi_register_systf(&t);
}
static void second(void) {
  printf("startup second\n");
  s_vpi_systf_data t = {.type = vpiSysTask, .tfname = "$two", .calltf = call, .user_data = "two"};
  vpi_register_systf(&t);
}
void (*vlog_startup_routines[])(void) = {first, second, 0};
void list(void) {
  vpiHandle systfs = vpi_iterate(vpiUserSystf, NULL);
  for (vpiHandle s; systfs && (s = vpi_scan(systfs));) {
    s_vpi_systf_data info = {0};
    vpi_get_systf_info(s, &info);
    printf("listed %s\n", info.tfname ? info.tfname : "null");
  }
}
