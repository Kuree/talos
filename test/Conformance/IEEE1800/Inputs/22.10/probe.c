#include "svdpi.h"
#include "vpi_user.h"
#include "sv_vpi_user.h"
int is_cell(const char *path) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
  return h ? vpi_get(vpiCellInstance, h) : -1;
}
