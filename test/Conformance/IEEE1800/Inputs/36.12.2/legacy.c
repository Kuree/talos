#define VPI_COMPATIBILITY_VERSION_1800v2017 1
#include "vpi_user.h"
int read_legacy(void){s_vpi_value v={.format=vpiIntVal};vpi_get_value(vpi_handle_by_name((PLI_BYTE8*)"top.value",0),&v);return v.value.integer;}
