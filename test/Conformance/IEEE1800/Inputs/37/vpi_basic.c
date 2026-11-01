#include "sv_vpi_user.h"
int probe_vpi_value(void) {
  vpiHandle object=vpi_handle_by_name((PLI_BYTE8*)"top.value",0);
  if(!object) return -1;
  s_vpi_value value={.format=vpiIntVal};
  vpi_get_value(object,&value); return value.value.integer;
}
