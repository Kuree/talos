#define VPI_COMPATIBILITY_VERSION_1364v2001 1
#include "sv_vpi_user.h"
#include <stdio.h>
void legacy(void) {
  vpiHandle it = vpi_iterate(vpiVariables, vpi_handle_by_name("top", 0)), h;
  int regs = 0, others = 0;
  while (it && (h = vpi_scan(it)))
    vpi_get(vpiType, h) == vpiReg ? regs++ : others++;
  printf("1364v2001 regs=%d others=%d\n", regs, others);
}
