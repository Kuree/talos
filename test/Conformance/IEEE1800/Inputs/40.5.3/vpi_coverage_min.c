#include "vpi_user.h"
#include "sv_vpi_user.h"
#include <stdio.h>
int c40_control(void) {
  vpiHandle h=vpi_handle_by_name("top",0);if(!h)return 0;
  int ok=vpi_control(vpiCoverageStop,vpiToggleCoverage,h);s_vpi_error_info e={0};int err=vpi_chk_error(&e);
  printf("VPI_CONTROL success=%d error=%d message=%s\n",ok,err,e.message?e.message:"");return ok;
}
