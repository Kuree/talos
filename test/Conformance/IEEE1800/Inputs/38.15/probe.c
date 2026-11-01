#include "sv_vpi_user.h"
int probe(void){vpiHandle h=vpi_handle_by_name((PLI_BYTE8*)"top.n",0);s_vpi_value v={.format=vpiIntVal};if(!h)return 0;vpi_get_value(h,&v);return v.value.integer==7;}
