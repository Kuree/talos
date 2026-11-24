#include "vpi_user.h"

// Puts `bits` (vpiBinStrVal) on the named net and prints any VPI error.
static void put(const char *name, const char *bits) {
  vpiHandle net = vpi_handle_by_name((PLI_BYTE8 *)name, 0);
  s_vpi_value value = {vpiBinStrVal};
  value.value.str = (PLI_BYTE8 *)bits;
  vpi_put_value(net, &value, 0, vpiNoDelay);
  s_vpi_error_info error;
  if (vpi_chk_error(&error))
    vpi_printf("put %s: %s\n", name, error.message);
  vpi_release_handle(net);
}

static PLI_INT32 put_nets(p_cb_data callback) {
  put("top.w", "10101010");
  put("top.masked", "01010101");
  return 0;
}

static PLI_INT32 start(p_cb_data callback) {
  static s_vpi_time time = {vpiSimTime, 0, 11};
  static s_cb_data delay = {cbAfterDelay, put_nets, 0, &time};
  vpi_register_cb(&delay);
  return 0;
}

static void startup(void) {
  static s_cb_data callback = {cbStartOfSimulation, start};
  vpi_register_cb(&callback);
}

void (*vlog_startup_routines[])(void) = {startup, 0};
