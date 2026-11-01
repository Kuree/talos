#include "sv_vpi_user.h"
#include <stdarg.h>
static int forward(char *format, ...) {
  va_list ap;
  va_start(ap, format);
  int n = vpi_vprintf(format, ap);
  va_end(ap);
  return n;
}
// Consumes the first argument, so the list is "already started" past it.
static int forward_rest(char *format, ...) {
  va_list ap;
  va_start(ap, format);
  (void)va_arg(ap, int);
  int n = vpi_vprintf(format, ap);
  va_end(ap);
  return n;
}
int probe(void) { return forward("a=%d b=%s\n", 12, "xy") + forward_rest("v=%d\n", 111, 222); }
