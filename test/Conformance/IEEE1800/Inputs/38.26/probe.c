#include "sv_vpi_user.h"
#include <stdio.h>
static void show(const char *label, PLI_UINT32 descriptor) {
  PLI_BYTE8 *name = vpi_mcd_name(descriptor);
  printf("%s=%s\n", label, name ? name : "null");
}
void names(int mcd, int other, int fd) {
  show("mcd", mcd);
  show("other", other);
  show("fd", fd);
  show("two channels", (PLI_UINT32)mcd | (PLI_UINT32)other);
  show("unopened", 1u << 20);
}
void closed(int mcd) { show("closed", mcd); }
