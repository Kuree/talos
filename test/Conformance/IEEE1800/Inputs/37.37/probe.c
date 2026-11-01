#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static vpiHandle port(const char *instance, const char *name) {
  vpiHandle p, it = vpi_iterate(vpiPort, vpi_handle_by_name(instance, 0));
  if (it)
    while ((p = vpi_scan(it)))
      if (str(vpiName, p)[0] == name[0])
        return p;
  return 0;
}
static void show(const char *label, vpiHandle path) {
  s_vpi_time t[2] = {{.type = vpiScaledRealTime}, {.type = vpiScaledRealTime}};
  s_vpi_delay d = {.da = t, .no_of_delays = 2, .time_type = vpiScaledRealTime};
  vpi_get_delays(path, &d);
  printf("delays %s rise=%g fall=%g\n", label, t[0].real, t[1].real);
}
void probe(void) {
  vpiHandle path = vpi_handle_multi(vpiInterModPath, port("top.d", "o"), port("top.r", "i"));
  printf("type=%s\n", str(vpiType, path));
  vpiHandle p, it = path ? vpi_iterate(vpiPort, path) : 0;
  if (it)
    while ((p = vpi_scan(it)))
      printf("port %s\n", str(vpiName, p));
  show("before", path);
  s_vpi_time t[2] = {{.type = vpiScaledRealTime, .real = 5}, {.type = vpiScaledRealTime, .real = 7}};
  s_vpi_delay d = {.da = t, .no_of_delays = 2, .time_type = vpiScaledRealTime};
  vpi_put_delays(path, &d);
  show("after", path);
}
