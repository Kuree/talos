#include "vpi_user.h"
static PLI_INT32 call(PLI_BYTE8*u){vpiHandle i=vpi_iterate(vpiArgument,vpi_handle(vpiSysTfCall,0));s_vpi_value v={.format=vpiIntVal};vpi_get_value(vpi_scan(i),&v);return 0;}
static void start(void){s_vpi_systf_data t={.type=vpiSysTask,.tfname="$touch",.calltf=call};vpi_register_systf(&t);}
void(*vlog_startup_routines[])(void)={start,0};
