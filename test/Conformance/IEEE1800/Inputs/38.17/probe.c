#include "sv_vpi_user.h"
int probe(void){s_vpi_vlog_info v={0};return vpi_get_vlog_info(&v)&&v.argc>=1&&v.product&&v.version;}
