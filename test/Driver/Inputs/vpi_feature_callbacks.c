#include "vpi_user.h"
#include <stdio.h>

// IEEE 1800-2023 38.36.3 feature callbacks: reset, interactive mode and
// interactive scope changes, with vpi_control (38.4).
static int stopping;

static unsigned long now(void) {
  s_vpi_time time = {.type = vpiSimTime};
  vpi_get_time(NULL, &time);
  return time.low;
}

static PLI_INT32 feature(p_cb_data callback) {
  printf("%s t=%lu", (const char *)callback->user_data, now());
  if (callback->reason == cbInteractiveScopeChange)
    printf(" obj=%s", callback->obj ? vpi_get_str(vpiFullName, callback->obj)
                                    : "null");
  printf("\n");
  fflush(stdout);
  // A reset is already running: another one is refused.
  if (callback->reason == cbStartOfReset)
    printf("nested reset=%d\n", vpi_control(vpiReset, 0, 9, 0));
  // A change from here delivers no callback, and this callback's failing
  // call is its own (cbPLIError), not the vpi_control that caused it.
  if (callback->reason == cbInteractiveScopeChange && callback->obj) {
    printf("nested scope=%d\n",
           vpi_control(vpiSetInteractiveScope, callback->obj));
    fflush(stdout);
    vpi_get(vpiType, NULL);
  }
  // A $stop while interactive does not enter again.
  if (callback->reason == cbEnterInteractive && stopping)
    printf("nested stop=%d\n", vpi_control(vpiStop, 0));
  fflush(stdout);
  return 0;
}

static PLI_INT32 pli_error(p_cb_data callback) {
  (void)callback;
  printf("cbPLIError\n");
  fflush(stdout);
  return 0;
}

static int count(void) {
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(vpi_handle_by_name("top.count", NULL), &value);
  return value.value.integer;
}

// At time 2 of the first run, set the interactive scope.
static PLI_INT32 at_two(p_cb_data callback) {
  (void)callback;
  int run = count();
  printf("timer count=%d\n", run);
  fflush(stdout);
  if (run == 0) {
    printf("null scope=%d\n", vpi_control(vpiSetInteractiveScope, NULL));
    fflush(stdout);
    vpiHandle variable = vpi_handle_by_name("top.count", NULL);
    printf("variable scope=%d\n", vpi_control(vpiSetInteractiveScope, variable));
    fflush(stdout);
    vpiHandle child = vpi_handle_by_name("top.u", NULL);
    int result = vpi_control(vpiSetInteractiveScope, child);
    printf("scope=%d level=%d\n", result, vpi_chk_error(NULL));
  }
  fflush(stdout);
  return 0;
}

// At time 7 of the first run, ask for a reset, which runs once this routine
// returns; its zero stop_value enters interactive mode after it.
static PLI_INT32 at_seven(p_cb_data callback) {
  (void)callback;
  if (count() != 0)
    return 0;
  printf("reset=%d\n", vpi_control(vpiReset, 0, 5, 0));
  printf("timer returns\n");
  fflush(stdout);
  return 0;
}

// From an imported function, the reset waits until the call returns, also
// past a callback the call itself causes, and then runs before anything else
// in the calling process and instead of final procedures.
void dpi_reset(void) {
  printf("dpi reset=%d\n", vpi_control(vpiReset, 1, 9, 0));
  fflush(stdout);
  vpi_get(vpiType, NULL);
  printf("dpi reset returns\n");
  fflush(stdout);
}

// vpiStop executes $stop once the routine returns.
void dpi_stop(void) {
  stopping = 1;
  printf("dpi stop=%d\n", vpi_control(vpiStop, 0));
  fflush(stdout);
}

// From a final procedure, past the scheduler's stop, $stop's callbacks and a
// reset happen at once.
void dpi_final(void) {
  printf("final stop=%d\n", vpi_control(vpiStop, 0));
  fflush(stdout);
  vpi_control(vpiReset, 1, 11, 0);
  printf("final reset returned\n");
  fflush(stdout);
}

// A failed call's status stays the application's across $scope.
void dpi_fail(void) { vpi_get(vpiType, NULL); }
void dpi_check(void) {
  printf("kept level=%d\n", vpi_chk_error(NULL));
  fflush(stdout);
}

static void enroll(PLI_INT32 reason, const char *name) {
  s_cb_data data = {.reason = reason, .cb_rtn = feature, .user_data = (PLI_BYTE8 *)name};
  if (!vpi_register_cb(&data))
    printf("%s not registered\n", name);
}

static void startup(void) {
  enroll(cbStartOfReset, "cbStartOfReset");
  enroll(cbEndOfReset, "cbEndOfReset");
  enroll(cbEnterInteractive, "cbEnterInteractive");
  enroll(cbExitInteractive, "cbExitInteractive");
  enroll(cbInteractiveScopeChange, "cbInteractiveScopeChange");
  // Accepted, but this simulation has no $save, $restart or user tasks it
  // cannot resolve.
  enroll(cbStartOfSave, "cbStartOfSave");
  enroll(cbEndOfRestart, "cbEndOfRestart");
  enroll(cbUnresolvedSystf, "cbUnresolvedSystf");
  static s_cb_data error = {.reason = cbPLIError, .cb_rtn = pli_error};
  static s_vpi_time two = {.type = vpiSimTime, .low = 2};
  static s_cb_data timer = {.reason = cbAfterDelay, .cb_rtn = at_two, .time = &two};
  static s_vpi_time seven = {.type = vpiSimTime, .low = 7};
  static s_cb_data later = {.reason = cbAfterDelay, .cb_rtn = at_seven, .time = &seven};
  if (!vpi_register_cb(&error) || !vpi_register_cb(&timer) ||
      !vpi_register_cb(&later))
    printf("timer not registered\n");
  fflush(stdout);
}

void (*vlog_startup_routines[])(void) = {startup, 0};
