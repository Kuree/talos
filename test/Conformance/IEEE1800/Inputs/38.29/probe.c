#include "sv_vpi_user.h"
#include <stdarg.h>
#include <stdio.h>
static int forward(PLI_UINT32 mcd, char *format, ...) {
  va_list ap;
  va_start(ap, format);
  int n = vpi_mcd_vprintf(mcd, format, ap);
  va_end(ap);
  return n;
}
// Consumes the first argument, so the list is "already started" past it.
static int forward_rest(PLI_UINT32 mcd, char *format, ...) {
  va_list ap;
  va_start(ap, format);
  (void)va_arg(ap, int);
  int n = vpi_mcd_vprintf(mcd, format, ap);
  va_end(ap);
  return n;
}
void probe(void) {
  PLI_UINT32 mcd = vpi_mcd_open("38.29.out");
  printf("count=%d\n", forward(mcd, "a=%d b=%s\n", 12, "xy"));
  printf("rest count=%d\n", forward_rest(mcd, "v=%d\n", 111, 222));
  vpi_mcd_close(mcd);
}
