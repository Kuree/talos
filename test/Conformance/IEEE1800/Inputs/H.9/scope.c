#include "svdpi.h"
#include <string.h>
int scope_ok(void){const char*n=svGetNameFromScope(svGetScope());return n&&!strcmp(n,"top.d");}
