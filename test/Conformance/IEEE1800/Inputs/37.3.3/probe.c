#include "sv_vpi_user.h"
int probe(void){vpiHandle h=vpi_handle_by_name((PLI_BYTE8*)"top.n",0);return h && vpi_get(vpiLineNo,h)>0 && vpi_get_str(vpiFile,h)!=0;}
