#include "sv_vpi_user.h"
#include <stdio.h>
void probe(int sv_mcd, int sv_fd) {
  PLI_UINT32 mcd = vpi_mcd_open("38.28.vpi.out");
  printf("count=%d\n", vpi_mcd_printf(mcd, "n=%d s=%s x=%x f=%5.2f\n", 7, "abc", 255, 1.5));
  // Bit 0 is the tool's output channel.
  vpi_mcd_printf(mcd | 1, "to the output channel too\n");
  vpi_mcd_printf(sv_mcd, "through a $fopen mcd\n");
  vpi_mcd_printf(sv_fd, "through an fd\n");
  vpi_mcd_close(mcd);
}
