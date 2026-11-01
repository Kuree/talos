#define VPI_COMPATIBILITY_VERSION_1800v2023 1
#include "vpi_user.h"
int compat_probe(void){vpiHandle h=vpi_handle_by_name((PLI_BYTE8*)"top.value",0);s_vpi_value v={.format=vpiIntVal};if(!h)return -1;vpi_get_value(h,&v);return v.value.integer;}
