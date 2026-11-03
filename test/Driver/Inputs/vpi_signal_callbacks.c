#include "vpi_user.h"
#include <signal.h>
#include <stdio.h>

// IEEE 1800-2023 38.36.3: a cbSignal callback runs at a safe point after its
// signal occurs, not in the signal handler.
static volatile sig_atomic_t own_handler_ran;
static vpiHandle third, late;
static int late_registered, finishing, raised_from_max;

static void own_handler(int signal) {
  (void)signal;
  own_handler_ran = 1;
}

static const char *name(int signal) {
  return signal == SIGUSR1 ? "USR1" : signal == SIGUSR2 ? "USR2" : "other";
}

static unsigned long now(void) {
  s_vpi_time time = {.type = vpiSimTime};
  vpi_get_time(NULL, &time);
  return time.low;
}

static PLI_INT32 on_signal(p_cb_data callback);

static vpiHandle watch(int signal, const char *label) {
  s_cb_data data = {.reason = cbSignal, .cb_rtn = on_signal, .index = signal,
                    .user_data = (PLI_BYTE8 *)label};
  return vpi_register_cb(&data);
}

static PLI_INT32 on_signal(p_cb_data callback) {
  const char *label = (const char *)callback->user_data;
  printf("%s %s t=%lu\n", label, name(callback->index), now());
  // A callback registered now waits for the next delivery, although its
  // signal is pending in this one.
  if (label[0] == 'f' && !late_registered++)
    printf("late registered=%d\n", (late = watch(SIGUSR2, "late")) != NULL);
  // Ending the simulation drops no signal that already arrived.
  if (label[0] == 'f' && finishing)
    printf("finish=%d\n", vpi_control(vpiFinish, 0));
  // Arrives after this slot's delivery started: the end of the simulation is
  // its safe point.
  if (label[0] == 'm' && !raised_from_max++)
    raise(SIGUSR1);
  if (callback->index == SIGUSR2 && third) {
    s_cb_data info;
    vpi_get_cb_info(third, &info);
    printf("info %s reason=%d own handler=%d\n", name(info.index),
           info.reason == cbSignal, own_handler_ran);
    printf("removed third=%d\n", vpi_remove_cb(third));
    third = NULL;
  } else if (callback->index == SIGUSR2 && late) {
    // The last callback of the signal: its earlier action is back.
    printf("removed late=%d\n", vpi_remove_cb(late));
    late = NULL;
  }
  fflush(stdout);
  return 0;
}

static PLI_INT32 on_timer(p_cb_data callback) {
  (void)callback;
  printf("timer t=%lu\n", now());
  fflush(stdout);
  return 0;
}

void raise_signals(void) {
  raise(SIGUSR2);
  raise(SIGUSR1);
  raise(SIGUSR1);
  printf("raised t=%lu\n", now());
  fflush(stdout);
}

void raise_again(void) { raise(SIGUSR2); }

void raise_last(void) {
  raise(SIGUSR2);
  printf("own handler=%d\n", own_handler_ran);
  fflush(stdout);
}

void raise_to_finish(void) {
  finishing = 1;
  raise(SIGUSR1);
  raise(64);
}

// Shutting VPI down gives a still watched signal its earlier action back.
__attribute__((destructor)) static void at_exit(void) {
  struct sigaction action;
  sigaction(SIGUSR1, NULL, &action);
  printf("exit USR1=%s\n", action.sa_handler == own_handler ? "own" : "other");
  fflush(stdout);
}

static void startup(void) {
  signal(SIGUSR1, own_handler);
  signal(SIGUSR2, own_handler);
  third = watch(SIGUSR2, "third");
  printf("first=%d\n", watch(SIGUSR1, "first") != NULL);
  printf("second=%d\n", watch(SIGUSR1, "second") != NULL);
  // No handler can catch SIGKILL; one returning from SIGSEGV would fault
  // again; 0 is no signal; 64 is the last one Linux has.
  printf("kill=%d level=%d\n", watch(SIGKILL, "kill") != NULL,
         vpi_chk_error(NULL));
  printf("segv=%d\n", watch(SIGSEGV, "segv") != NULL);
  printf("zero=%d\n", watch(0, "zero") != NULL);
  printf("64=%d\n", watch(64, "max") != NULL);
  static s_vpi_time four = {.type = vpiSimTime, .low = 4};
  static s_cb_data timer = {.reason = cbAfterDelay, .cb_rtn = on_timer, .time = &four};
  vpi_register_cb(&timer);
  fflush(stdout);
}

void (*vlog_startup_routines[])(void) = {startup, 0};
