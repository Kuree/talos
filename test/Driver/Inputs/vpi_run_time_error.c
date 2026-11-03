#include "vpi_user.h"
#include <stdio.h>

// IEEE 1800-2023 38.36.3: cbError callbacks run when a simulation run-time
// error occurs; vpi_chk_error retrieves the error inside the callback.
static vpiHandle second_handle;

static PLI_INT32 run_time_error(p_cb_data callback) {
  s_vpi_error_info info;
  PLI_INT32 level = vpi_chk_error(&info);
  printf("cbError user=%s level=%d message=%s\n", callback->user_data, level,
         info.message);
  // A VPI call inside the callback starts a fresh error status.
  vpi_get(vpiTimePrecision, NULL);
  printf("after a call level=%d\n", vpi_chk_error(NULL));
  fflush(stdout);
  return 0;
}

// Runs once: it removes itself during delivery, and still sees the error the
// earlier callback's own VPI call reset.
static PLI_INT32 second(p_cb_data callback) {
  printf("cbError user=%s level=%d\n", callback->user_data,
         vpi_chk_error(NULL));
  printf("removed=%d\n", vpi_remove_cb(second_handle));
  fflush(stdout);
  return 0;
}

static void startup(void) {
  static s_cb_data first = {
      .reason = cbError, .cb_rtn = run_time_error, .user_data = "error"};
  static s_cb_data other = {
      .reason = cbError, .cb_rtn = second, .user_data = "second"};
  printf("cbError registered=%d\n", vpi_register_cb(&first) != 0);
  second_handle = vpi_register_cb(&other);
  printf("cbError registered=%d\n", second_handle != 0);
  fflush(stdout);
}

void (*vlog_startup_routines[])(void) = {startup, 0};
