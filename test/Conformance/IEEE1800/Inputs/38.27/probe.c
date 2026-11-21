#include "sv_vpi_user.h"
#include <stdio.h>
static int single(PLI_UINT32 mcd) { return mcd && !(mcd & (mcd - 1)); }

static int reopen_when_full(PLI_UINT32 existing, PLI_UINT32 used) {
  PLI_UINT32 opened = 0;
  for (unsigned i = 0; i < 31; ++i) {
    char path[32];
    snprintf(path, sizeof(path), "38.27.fill%u.out", i);
    PLI_UINT32 channel = vpi_mcd_open(path);
    if (!channel)
      break;
    if (!single(channel) || (channel & (used | opened | 0x80000001u)))
      return 0;
    opened |= channel;
  }
  int ok = vpi_mcd_open("38.27.overflow.out") == 0 &&
           vpi_mcd_open("38.27.a.out") == existing;
  if (vpi_mcd_close(opened))
    return 0;
  PLI_UINT32 reused = vpi_mcd_open("38.27.reused.out");
  return ok && (reused & opened) && !vpi_mcd_close(reused);
}

int probe(int sv_mcd, int sv_fd) {
  PLI_UINT32 a = vpi_mcd_open("38.27.a.out"), b = vpi_mcd_open("38.27.b.out");
  // Bit 0 is the tool's output channel; the MSB marks an fd.
  printf("single bits=%d distinct=%d reserved=%d\n", single(a) && single(b), a != b,
         ((a | b) & (1u | 1u << 31)) != 0);
  vpi_mcd_printf(a, "before reopening\n");
  printf("reopen same=%d $fopen same=%d alias same=%d\n",
         vpi_mcd_open("38.27.a.out") == a,
         vpi_mcd_open("38.27.sv.out") == (PLI_UINT32)sv_mcd,
         vpi_mcd_open("./38.27.a.out") == a);
  PLI_UINT32 fd = vpi_mcd_open("./38.27.fd.out");
  printf("tagged descriptor reused=%d write rejected=%d\n",
         fd == (PLI_UINT32)sv_fd, vpi_mcd_printf(fd, "wrong channel\n") == EOF);
  printf("bad path=%u\n", vpi_mcd_open("no-such-directory/file"));
  printf("reopen when full and recycle=%d\n",
         reopen_when_full(a, a | b | (PLI_UINT32)sv_mcd));
  vpi_mcd_printf(a, "to a\n");
  vpi_mcd_printf(b, "to b\n");
  vpi_mcd_printf(a | b, "to both\n");
  vpi_mcd_close(a | b);
  return (int)vpi_mcd_open("38.27.from-vpi.out");
}

int closed(int mcd) { return vpi_mcd_name((PLI_UINT32)mcd) == NULL; }
