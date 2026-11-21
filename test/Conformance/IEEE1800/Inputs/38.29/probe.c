#include "sv_vpi_user.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
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

static int matches(const char *path, const char *expected, size_t size) {
  char bytes[1028];
  FILE *file = fopen(path, "rb");
  if (!file)
    return 0;
  int ok = size == sizeof(bytes) && fread(bytes, 1, size, file) == size &&
           fgetc(file) == EOF && memcmp(bytes, expected, size) == 0;
  fclose(file);
  return ok;
}

static int broadcast(void) {
  PLI_UINT32 a = vpi_mcd_open("38.29.a.out");
  PLI_UINT32 b = vpi_mcd_open("38.29.b.out");
  char word[] = "abc";
  char expected[1028] = "abc";
  memset(expected + 4, ' ', 1023);
  expected[1027] = 'x';
#ifdef _WIN32
  int previous = _set_printf_count_output(1);
#endif
  // The %hhn changes the string after it was printed. Both destinations
  // must receive its original bytes, including the following NUL from %c.
  int count =
      forward(a | b, "%s%hhn%c%1024s", word, (signed char *)word, 0, "x");
#ifdef _WIN32
  _set_printf_count_output(previous);
#endif
  return vpi_mcd_close(a | b) == 0 && count == (int)sizeof(expected) &&
         word[0] == 3 && matches("38.29.a.out", expected, sizeof(expected)) &&
         matches("38.29.b.out", expected, sizeof(expected));
}

void probe(void) {
  PLI_UINT32 mcd = vpi_mcd_open("38.29.out");
  printf("count=%d\n", forward(mcd, "a=%d b=%s\n", 12, "xy"));
  printf("rest count=%d\n", forward_rest(mcd, "v=%d\n", 111, 222));
  vpi_mcd_close(mcd);
  printf("identical binary broadcast=%d\n", broadcast());
}
