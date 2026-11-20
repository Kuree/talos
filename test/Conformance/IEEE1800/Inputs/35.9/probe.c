#include "svdpi.h"
#include <stdio.h>

extern int wait_sv(void);
static int disabled;

int call_c(svBit call_again) {
  int result = wait_sv();
  disabled = result == 1 && svIsDisabledState();
  if (call_again && disabled) {
    puts("attempting a second export");
    wait_sv();
  }
  return result;
}

int status(void) { return disabled; }
