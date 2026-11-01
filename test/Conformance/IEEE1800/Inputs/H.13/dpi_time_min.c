#include "svdpi.h"
#include <stdint.h>
extern int svGetTimeUnit(const svScope scope,int32_t *time_unit);
int c35_time_min(void) {
  int32_t unit=0;return svGetTimeUnit(svGetScope(),&unit)==0 && unit==-9;
}
