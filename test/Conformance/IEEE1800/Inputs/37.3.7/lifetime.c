#include "vpi_user.h"
static vpiHandle h;
int cached(void){if(!h)h=vpi_handle_by_name((PLI_BYTE8*)"top.value",0);s_vpi_value v={.format=vpiIntVal};vpi_get_value(h,&v);return v.value.integer;}
