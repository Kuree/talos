#include "vpi_user.h"
static int count,seen=-1;
static PLI_INT32 capture(p_cb_data cb){s_vpi_value v={.format=vpiIntVal};vpi_get_value(vpi_handle_by_name((PLI_BYTE8*)"top.x",0),&v);seen=v.value.integer;++count;return 0;}
int arm(void){static s_vpi_time t={.type=vpiSimTime,.low=1};s_cb_data cb={.reason=cbAfterDelay,.cb_rtn=capture,.time=&t};return vpi_register_cb(&cb)!=0;}
int sample(void){return count==1?seen:-1;}
