#include "sv_vpi_user.h"
int probe(void){s_vpi_time t={.type=vpiSimTime};vpi_get_time(0,&t);return t.high==0&&t.low==0;}
