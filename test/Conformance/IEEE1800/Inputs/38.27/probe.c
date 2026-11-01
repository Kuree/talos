#include "sv_vpi_user.h"
#include <stdio.h>
static int single(PLI_UINT32 mcd) { return mcd && !(mcd & (mcd - 1)); }
void probe(int sv_mcd) {
  PLI_UINT32 a = vpi_mcd_open("38.27.a.out"), b = vpi_mcd_open("38.27.b.out");
  // Bit 0 is the tool's output channel; the MSB marks an fd.
  printf("single bits=%d distinct=%d reserved=%d\n", single(a) && single(b), a != b,
         ((a | b) & (1u | 1u << 31)) != 0);
  printf("reopen same=%d $fopen same=%d\n", vpi_mcd_open("38.27.a.out") == a,
         vpi_mcd_open("38.27.sv.out") == (PLI_UINT32)sv_mcd);
  printf("bad path=%u\n", vpi_mcd_open("no-such-directory/file"));
  vpi_mcd_printf(a, "to a\n");
  vpi_mcd_printf(b, "to b\n");
  vpi_mcd_printf(a | b, "to both\n");
  vpi_mcd_close(a | b);
}
