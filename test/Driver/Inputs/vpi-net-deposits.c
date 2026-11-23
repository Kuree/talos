#include "sv_vpi_user.h"
#include <stdio.h>

// Puts `value` (vpiBinStrVal) on the named object with `flags`, and prints
// the VPI error if there is one.
static void write(const char *name, const char *value, PLI_INT32 flags) {
  s_vpi_value data = {vpiBinStrVal, {0}};
  data.value.str = (PLI_BYTE8 *)value;
  vpi_put_value(vpi_handle_by_name((PLI_BYTE8 *)name, NULL), &data, NULL,
                flags);
  s_vpi_error_info info;
  if (vpi_chk_error(&info) && info.message)
    printf("put %s: %s\n", name, info.message);
}

void put(const char *name, const char *value) {
  write(name, value, vpiNoDelay);
}

void force_net(const char *name, const char *value) {
  write(name, value, vpiForceFlag);
}

void release_net(const char *name) {
  s_vpi_value data = {vpiBinStrVal, {0}};
  vpi_put_value(vpi_handle_by_name((PLI_BYTE8 *)name, NULL), &data, NULL,
                vpiReleaseFlag);
  s_vpi_error_info info;
  if (vpi_chk_error(&info) && info.message)
    printf("release %s: %s\n", name, info.message);
}
