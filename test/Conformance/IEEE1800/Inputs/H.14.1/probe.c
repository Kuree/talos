#include <string.h>
#include "svdpi.h"
int known(void) { return !strcmp(svDpiVersion(), "1800-2005") || !strcmp(svDpiVersion(), "SV3.1a"); }
int vlen(void) { return (int)strlen(svDpiVersion()); }
