#include "sv_vpi_user.h"
int probe(void){PLI_INT32 ix[2]={1,1};vpiHandle a=vpi_handle_by_name((PLI_BYTE8*)"top.a",0),h=a?vpi_handle_by_multi_index(a,2,ix):0;s_vpi_value v={.format=vpiIntVal};if(!h)return 0;vpi_get_value(h,&v);return v.value.integer==7;}
