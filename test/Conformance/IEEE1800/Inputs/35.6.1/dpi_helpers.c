#include "svdpi.h"
int dpi_sum(const svOpenArrayHandle values) {
  int sum=0;
  for(int i=svLow(values,1);i<=svHigh(values,1);++i) {
    const int *value=(const int*)svGetArrElemPtr1(values,i);
    if(!value) return -999;
    sum+=*value;
  }
  return sum;
}
