#include "vpi_user.h"
#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
int c36_info_time(void) {
  s_vpi_vlog_info info={0}; s_vpi_time t={0}; t.type=vpiSimTime; vpi_get_time(0,&t);
  int ok=vpi_get_vlog_info(&info); printf("VPI_INFO ok=%d argc=%d ticks=%u:%u\n",ok,info.argc,t.high,t.low);
  return ok && info.argc>=1 && info.product && info.version && t.high==0 && t.low==1000;
}
