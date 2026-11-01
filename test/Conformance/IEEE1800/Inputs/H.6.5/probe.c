#include "svdpi.h"
extern int ex(int);
int ctx(int x) { return ex(x) + 1; }
int plain(int x) { return x * x; }
const char *ctxname(void) { return svGetNameFromScope(svGetScope()); }
