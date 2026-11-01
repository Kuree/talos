#include "sv_vpi_user.h"
int probe(void){vpiHandle a=vpi_handle_by_name((PLI_BYTE8*)"top.a",0),h=a?vpi_handle_by_index(a,1):0;s_vpi_value v={.format=vpiIntVal};if(!h)return 0;vpi_get_value(h,&v);return v.value.integer==7;}
