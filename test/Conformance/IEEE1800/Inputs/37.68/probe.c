#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void show(vpiHandle control) {
  vpiHandle d = vpi_handle(vpiDelay, control), stmt = vpi_handle(vpiStmt, control);
  s_vpi_time da[1] = {{.type = vpiSimTime}};
  s_vpi_delay delay = {.da = da, .no_of_delays = 1, .time_type = vpiSimTime};
  vpi_get_delays(control, &delay);
  if (d)
    printf(" delay=%d", value(d));
  else
    printf(" delay=null");
  printf(" get_delays=%u", da[0].low);
  printf(" stmt=%s\n", stmt ? vpi_get_str(vpiType, stmt) : "null");
}

void probe(void) {
  vpiHandle p = vpi_scan(vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0)));
  vpiHandle it = vpi_iterate(vpiStmt, vpi_handle(vpiStmt, p)), s;
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type == vpiDelayControl) {
      printf("%s", vpi_get_str(vpiType, s));
      show(s);
    } else if (type == vpiAssignment) {
      vpiHandle control = vpi_handle(vpiDelayControl, s);
      printf("assignment control=%s", control ? vpi_get_str(vpiType, control) : "null");
      if (control)
        show(control);
      else
        printf("\n");
    }
  }
}
