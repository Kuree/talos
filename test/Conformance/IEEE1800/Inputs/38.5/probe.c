#include "sv_vpi_user.h"
#include <stdio.h>
#include <unistd.h>
void probe(void) {
  // A partial line stays in a buffer until flushed. write() bypasses every buffer, so without
  // the flush its text would come first.
  vpi_printf("partial line, then ");
  int status = vpi_flush();
  static const char raw[] = "an unbuffered write\n";
  if (write(1, raw, sizeof raw - 1) < 0)
    printf("write failed\n");
  printf("flush=%d\n", status);
}
