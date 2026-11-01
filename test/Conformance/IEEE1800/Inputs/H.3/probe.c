#include "svdpi.h"
int c_named(void) { return 7; }
const char *ctx_name(void) { return svGetNameFromScope(svGetScope()); }
int enc(void) { return sv_z * 10 + sv_x; }
