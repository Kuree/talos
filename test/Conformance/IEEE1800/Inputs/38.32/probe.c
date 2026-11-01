#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  vpiHandle g = vpi_handle_by_name("top.g", 0);
  s_vpi_time da[2] = {{.type = vpiSimTime, .low = 5}, {.type = vpiSimTime, .low = 7}};
  s_vpi_delay d = {.da = da, .no_of_delays = 2, .time_type = vpiSimTime};
  vpi_put_delays(g, &d);
  da[0].low = da[1].low = 0;
  vpi_get_delays(g, &d);
  printf("read back %u %u\n", da[0].low, da[1].low);
}
