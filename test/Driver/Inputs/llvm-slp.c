#include <stdlib.h>

int slp_source(int index) {
  static int next;
  if (index != next++)
    abort();
  return index;
}
