#include "svdpi.h"
#include "vpi_user.h"
int f(void){return svGetScope()!=0 && vpi_handle_by_name((PLI_BYTE8*)"top",0)!=0;}
