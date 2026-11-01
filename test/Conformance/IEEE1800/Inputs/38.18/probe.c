#include "sv_vpi_user.h"
int probe(void){vpiHandle n=vpi_handle_by_name((PLI_BYTE8*)"top.n",0),m=vpi_handle_by_name((PLI_BYTE8*)"top",0);return n&&m&&vpi_compare_objects(vpi_handle(vpiModule,n),m);}
