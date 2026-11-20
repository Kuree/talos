#include "sv_vpi_user.h"
#include "svdpi.h"
#include <stddef.h>

int check_time(const char *name, int unit_exp, int precision_exp, double now) {
  svScope scope = svGetScope();
  vpiHandle object = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
  int32_t unit, precision;
  svTimeVal dpi_time = {.type = sv_scaled_real_time};
  s_vpi_time vpi_time = {.type = vpiScaledRealTime};
  if (!scope || !object || svGetTimeUnit(scope, &unit) ||
      svGetTimePrecision(scope, &precision) || svGetTime(scope, &dpi_time))
    return 0;
  vpi_get_time(object, &vpi_time);
  if (unit != unit_exp || precision != precision_exp || dpi_time.real != now ||
      vpi_get(vpiTimeUnit, object) != unit ||
      vpi_get(vpiTimePrecision, object) != precision || vpi_time.real != now)
    return 0;
  if (svGetTimeUnit(NULL, &unit) || svGetTimePrecision(NULL, &precision) ||
      unit != -12 || precision != -12 || vpi_get(vpiTimeUnit, NULL) != -12 ||
      vpi_get(vpiTimePrecision, NULL) != -12)
    return 0;
  if (vpi_get(vpiType, object) == vpiPackage) {
    vpiHandle member = vpi_handle_by_name("top::marker", NULL);
    vpiHandle variables = vpi_iterate(vpiVariables, object);
    if (!member || !variables ||
        !vpi_compare_objects(member, vpi_scan(variables)) ||
        !vpi_compare_objects(object, vpi_handle(vpiScope, member)) ||
        !vpi_compare_objects(object, vpi_handle(vpiInstance, member)) ||
        vpi_scan(variables))
      return 0;
    vpi_get_time(member, &vpi_time);
    return vpi_time.real == now;
  }
  return 1;
}
