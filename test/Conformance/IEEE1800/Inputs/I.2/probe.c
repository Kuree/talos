#include <string.h>
#include <stdint.h>
#include "svdpi.h"
#include "vpi_user.h"
const char *nm(void) { return svGetNameFromScope(svGetScope()); }
int look(void) { svScope s = svGetScopeFromName("top"); return s && s == svGetScope() && !strcmp(svGetNameFromScope(s), "top"); }
int ud(void) {
  static int key, val = 42; svScope s = svGetScope(); int *p;
  if (svPutUserData(s, &key, &val) != 0) return -1;
  p = (int *)svGetUserData(s, &key); return p && *p == 42;
}
int tu(void) { int32_t u = 0, p = 0; svGetTimeUnit(svGetScope(), &u); svGetTimePrecision(svGetScope(), &p); return (-u) * 100 + (-p); }
int tm(void) { svTimeVal t; t.type = vpiSimTime; t.high = 0; t.low = 0; svGetTime(svGetScope(), &t); return (int)t.low; }
