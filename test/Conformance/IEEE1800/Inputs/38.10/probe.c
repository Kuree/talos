#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  vpiHandle g = vpi_handle_by_name("top.g", 0);
  if (!g) { printf("gate=null\n"); return; }
  printf("gate type=%s\n", vpi_get_str(vpiType, g));
  s_vpi_time da[3] = {{0}};
  s_vpi_delay d = {.da = da, .no_of_delays = 3, .time_type = vpiSimTime};
  vpi_get_delays(g, &d);
  printf("gate sim %u %u %u\n", da[0].low, da[1].low, da[2].low);
  d.time_type = vpiScaledRealTime;
  vpi_get_delays(g, &d);
  printf("gate scaled %.2f %.2f %.2f\n", da[0].real, da[1].real, da[2].real);
  d.time_type = vpiSimTime;
  vpi_get_delays(vpi_handle_by_name("top.n", 0), &d);
  printf("net sim %u %u %u\n", da[0].low, da[1].low, da[2].low);
}
