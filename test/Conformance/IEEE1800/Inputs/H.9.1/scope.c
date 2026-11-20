#include "svdpi.h"

const char *where_am_i(void) { return svGetNameFromScope(svGetScope()); }

int read_scope(const char **name) {
  *name = where_am_i();
  return 0;
}
