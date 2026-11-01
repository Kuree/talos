#include "vpi_user.h"
#include <stdint.h>
static PLI_INT32 invoke(PLI_BYTE8*u){s_vpi_value v={.format=vpiIntVal};v.value.integer=(int)(intptr_t)u;vpi_put_value(vpi_handle(vpiSysTfCall,0),&v,0,vpiNoDelay);return 0;}
static void start(void){s_vpi_systf_data t={.type=vpiSysFunc,.sysfunctype=vpiIntFunc,.calltf=invoke};t.tfname="$Conformance";t.user_data=(PLI_BYTE8*)(intptr_t)1;vpi_register_systf(&t);t.tfname="$conformance";t.user_data=(PLI_BYTE8*)(intptr_t)2;vpi_register_systf(&t);}
void(*vlog_startup_routines[])(void)={start,0};
