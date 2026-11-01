#include "vpi_user.h"
#include <stdio.h>
int c37_find(const char *name) {
  vpiHandle h=vpi_handle_by_name((PLI_BYTE8 *)name,0);s_vpi_error_info e={0};int err=vpi_chk_error(&e);
  printf("LOOKUP name=%s found=%d error=%d message=%s\n",name,h!=0,err,e.message?e.message:"");return h!=0;
}
