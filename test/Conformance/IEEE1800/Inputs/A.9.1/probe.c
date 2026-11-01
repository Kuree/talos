#include <string.h>
#include "svdpi.h"
#include "vpi_user.h"
#include "sv_vpi_user.h"
int attr(const char *path, const char *name) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)path, 0), a, it;
  if (!h || !(it = vpi_iterate(vpiAttribute, h))) return -1;
  while ((a = vpi_scan(it))) {
    if (!strcmp(vpi_get_str(vpiName, a), name)) {
      s_vpi_value v; v.format = vpiIntVal; vpi_get_value(a, &v); vpi_free_object(it); return v.value.integer;
    }
  }
  return -1;
}
