#include "sv_vpi_user.h"
#include <stdio.h>

// Writes `text` (vpiBinStrVal) to the object `name` names, with `flags`.
static void put(const char *name, const char *text, PLI_INT32 flags) {
  vpiHandle object = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
  s_vpi_value value = {vpiBinStrVal, {0}};
  value.value.str = (PLI_BYTE8 *)text;
  s_vpi_time time = {vpiSimTime, 0, 0, 0};
  vpi_put_value(object, &value, &time, flags);
  s_vpi_error_info info;
  printf("%s=%s: %s\n", name, text,
         vpi_chk_error(&info) && info.message ? info.message : "written");
}

void write_elements(void) {
  put("top.ints[1]", "101010", vpiNoDelay);
  put("top.mem[3]", "1x0z", vpiNoDelay);
  put("top.vec[2]", "1", vpiNoDelay);
  put("top.grid[1][0]", "0110", vpiNoDelay);
  put("top.packed_s.hi", "1111", vpiNoDelay);
  put("top.unpacked_s.a", "111", vpiNoDelay);
  put("top.tagged_u.word", "1", vpiNoDelay);
  put("top.ints[2]", "1", vpiForceFlag);
  put("top.obj.items[0]", "1", vpiNoDelay);
  put("top.wide[1]", "1000000000000000000000000000000000000001", vpiNoDelay);
  put("top.mixed.a", "zx1", vpiNoDelay);
  put("top.mixed_p.a", "x1z0", vpiNoDelay);
  put("top.whole_int", "1z", vpiNoDelay);
  put("top.names[0]", "1", vpiNoDelay);
  put("top.name", "1", vpiNoDelay);
}
