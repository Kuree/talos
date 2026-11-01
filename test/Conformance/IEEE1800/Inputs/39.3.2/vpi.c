#include "vpi_user.h"
#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static vpiHandle named(const char *n) {
  vpiHandle h=vpi_handle_by_name((PLI_BYTE8 *)n,0); s_vpi_error_info e={0}; int err=vpi_chk_error(&e);
  printf("VPI_HANDLE name=%s found=%d error=%d message=%s\n",n,h!=0,err,e.message?e.message:""); return h;
}
int c39_static_assertion(void) {
  vpiHandle h=named("top.check_one"); return h && vpi_get(vpiType,h)==vpiAssert;
}
