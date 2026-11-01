#include "sv_vpi_user.h"
int probe(void){s_vpi_error_info e={0};return vpi_chk_error(&e)==0;}
