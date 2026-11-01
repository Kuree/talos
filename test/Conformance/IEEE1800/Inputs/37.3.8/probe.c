#include "sv_vpi_user.h"
int probe(void){vpiHandle h=vpi_handle_by_name((PLI_BYTE8*)"top.n",0);return h && vpi_release_handle(h);}
