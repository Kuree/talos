#include "vpi_user.h"
#include "talos/Version.h"
#include <string.h>

static PLI_INT32 report_info(p_cb_data callback) {
  s_vpi_vlog_info info;
  if (!vpi_get_vlog_info(&info) || !info.product || !info.version ||
      strcmp(info.product, "talos") != 0 ||
      strcmp(info.version, TALOS_VERSION_STRING) != 0) {
    vpi_printf("VPI simulator info mismatch\n");
    return 0;
  }
  vpi_printf("VPI simulator info matches VERSION: %s %s\n", info.product,
             info.version);
  return 0;
}

static void startup(void) {
  static s_cb_data callback = {cbEndOfCompile, report_info};
  vpi_register_cb(&callback);
}

void (*vlog_startup_routines[])(void) = {startup, 0};
