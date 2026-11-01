#include "svdpi.h"
#include <stdio.h>
extern int sv_f(void);
int c35_export_same(void) {
  svScope child=svGetScopeFromName("top.child");
  printf("EXPORT_SCOPE found=%d\n",child!=0);if(!child)return -100;
  svSetScope(child);return sv_f();
}
