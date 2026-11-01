#include "sv_vpi_user.h"
int probe_vpi_array(void) {
  vpiHandle array=vpi_handle_by_name((PLI_BYTE8*)"top.a",0);
  if(!array) return -1;
  int sum=0;
  for(int i=5;i<=7;++i) {
    vpiHandle elem=vpi_handle_by_index(array,i);
    if(!elem) return -2;
    s_vpi_value value={.format=vpiIntVal};
    vpi_get_value(elem,&value); sum+=value.value.integer;
  }
  return sum;
}
