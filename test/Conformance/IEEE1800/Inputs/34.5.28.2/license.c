#include <stdio.h>
#include <string.h>
int check(const char *feature) {
  printf("license feature=%s\n", feature);
  fflush(stdout);
  return strcmp(feature, "licensed") ? 13 : 42;
}
void release(void) {
  puts("license released");
  fflush(stdout);
}
