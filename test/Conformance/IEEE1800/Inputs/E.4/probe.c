#include "vpi_user.h"
int probe(void){vpiHandle h=vpi_handle_by_name((PLI_BYTE8*)"top",0);return h && vpi_get(vpiDefDelayMode,h)==vpiDelayModeDistrib;}
