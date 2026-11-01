#include "sv_vpi_user.h"
#include <stdio.h>
void probe(int sv_mcd) {
  PLI_UINT32 mcd = vpi_mcd_open("38.24.vpi.out");
  vpi_mcd_printf(mcd, "written before the close\n");
  PLI_UINT32 status = vpi_mcd_close(mcd);
  printf("close=%u name=%s\n", status, vpi_mcd_name(mcd) ? "open" : "null");
  // On error it returns "the mcd value of the unclosed channels".
  printf("closed again=%d\n", vpi_mcd_close(mcd) == mcd);
  // Descriptor 1 "cannot be closed using vpi_mcd_close()".
  printf("channel 1 kept=%d\n", vpi_mcd_close(1) == 1);
  status = vpi_mcd_close(sv_mcd);
  printf("$fopen close=%u name=%s\n", status, vpi_mcd_name(sv_mcd) ? "open" : "null");
}
