#include "sv_vpi_user.h"
#include <stdio.h>
void probe(int sv_mcd, int sv_fd) {
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
  PLI_UINT32 valid = vpi_mcd_open("38.24.valid.out");
  PLI_UINT32 closed = vpi_mcd_open("38.24.closed.out");
  vpi_mcd_close(closed);
  status = vpi_mcd_close(valid | closed | 1);
  printf("mixed close=%d closed valid=%d\n", status == (closed | 1),
         vpi_mcd_name(valid) == NULL);
  status = vpi_mcd_close((PLI_UINT32)sv_fd);
  printf("$fopen fd close=%u name=%s\n", status,
         vpi_mcd_name((PLI_UINT32)sv_fd) ? "open" : "null");
}
