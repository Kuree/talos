#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  PLI_UINT32 mcd = vpi_mcd_open("38.25.out");
  vpi_mcd_printf(mcd, "first line\n");
  printf("flush=%d\n", vpi_mcd_flush(mcd));
  // Without the flush the text would still be in the output buffer.
  char line[32] = "nothing";
  FILE *reader = fopen("38.25.out", "r");
  if (reader) {
    if (!fgets(line, sizeof line, reader))
      snprintf(line, sizeof line, "empty\n");
    fclose(reader);
  }
  printf("read while open: %s", line);
  vpi_mcd_printf(mcd, "second line\n");
  vpi_mcd_close(mcd);
}
