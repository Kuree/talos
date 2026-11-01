#include "svdpi.h"
extern int sv_export_calc(int a);
int c35_export_call(void) {
  svScope before=svGetScope(); svScope child=svGetScopeFromName("top.child");
  if(!before || !child)return -100;
  svSetScope(child); int a=sv_export_calc(3); svSetScope(before); int b=sv_export_calc(3);
  return a*1000+b;
}
