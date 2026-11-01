#include "sv_vpi_user.h"
int probe(void){vpiHandle a=vpi_handle_by_name((PLI_BYTE8*)"top.n",0),b=vpi_handle_by_name((PLI_BYTE8*)"top.n",0);return a&&b&&vpi_compare_objects(a,b);}
