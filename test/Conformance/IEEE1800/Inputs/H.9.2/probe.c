#include "svdpi.h"
extern int inc(int);
int callex(int x) { return inc(x); }
const char *who(void) { return svGetNameFromScope(svGetScope()); }
