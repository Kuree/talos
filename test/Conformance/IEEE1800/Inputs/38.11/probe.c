#include "sv_vpi_user.h"
#include <string.h>
int probe(void){vpiHandle h=vpi_handle_by_name((PLI_BYTE8*)"top.n",0);const char*s=h?vpi_get_str(vpiFullName,h):0;return s&&!strcmp(s,"top.n");}
