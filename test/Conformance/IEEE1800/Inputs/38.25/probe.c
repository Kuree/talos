#include "sv_vpi_user.h"
#include <stdio.h>
static void read_line(const char *label, const char *name, unsigned number) {
  char line[32] = "nothing";
  FILE *reader = fopen(name, "r");
  if (reader) {
    for (unsigned i = 0; i < number; ++i) {
      if (!fgets(line, sizeof line, reader)) {
        snprintf(line, sizeof line, "empty\n");
        break;
      }
    }
    fclose(reader);
  }
  printf("%s: %s", label, line);
}

void probe(void) {
  PLI_UINT32 mcd = vpi_mcd_open("38.25.out");
  vpi_mcd_printf(mcd | 1, "first line\n");
  printf("flush=%d\n", vpi_mcd_flush(mcd | 1));
  read_line("read while open", "38.25.out", 1);
  read_line("log while open", "38.25.log", 1);
  vpi_mcd_printf(mcd, "second line\n");
  vpi_mcd_close(mcd);
  vpi_printf("buffered before pause\n");
}

void flush_paused(void) {
  vpi_printf("stdout while paused\n");
  printf("paused flush=%d\n", vpi_mcd_flush(1));
  read_line("paused log while open", "38.25.log", 2);
}
