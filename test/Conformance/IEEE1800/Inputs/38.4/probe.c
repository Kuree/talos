#include "sv_vpi_user.h"
#include <stdio.h>
static int calls;
void probe(int stop) {
  if (stop) {
    printf("stop=%d\n", vpi_control(vpiStop, 0));
  } else if (++calls == 1) {
    printf("scope=%d\n", vpi_control(vpiSetInteractiveScope, vpi_handle_by_name("top", 0)));
    // D.8: a nonzero stop_value begins processing immediately after the reset.
    printf("reset=%d\n", vpi_control(vpiReset, 1, 0, 0));
  } else {
    printf("finish=%d\n", vpi_control(vpiFinish, 0));
  }
}
