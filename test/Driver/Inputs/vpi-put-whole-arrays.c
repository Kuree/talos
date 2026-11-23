#include "sv_vpi_user.h"
#include <stdio.h>

// IEEE 1800-2023 37.17 detail 11 and 37.26 detail 1: whole arrays (fixed,
// dynamic, queue, associative), unpacked structures and class variables have
// no value property, so vpi_put_value must refuse them and leave them
// unchanged.
void put(void) {
  static const char *names[] = {"top.fixed",  "top.dyn", "top.q",    "top.aa",
                                "top.record", "top.obj", "top.plain"};
  for (unsigned i = 0; i != sizeof(names) / sizeof(names[0]); ++i) {
    s_vpi_value value = {vpiIntVal, {0}};
    value.value.integer = 12345;
    vpi_put_value(vpi_handle_by_name((PLI_BYTE8 *)names[i], NULL), &value, NULL,
                  vpiNoDelay);
    s_vpi_error_info info;
    printf("%s: %s\n", names[i],
           vpi_chk_error(&info) && info.message ? info.message : "written");
  }
}
