#include "svdpi.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef struct { int i; double r; } c35_pair;
int c35_open_bounds(const svOpenArrayHandle a,int left,int right) {
  int sum=0;
  if(svDimensions(a)!=1 || svLeft(a,1)!=left || svRight(a,1)!=right || svSize(a,1)!=3) return -100;
  for(int i=svLow(a,1);i<=svHigh(a,1);++i) { int *p=svGetArrElemPtr1(a,i); if(!p) return -101; sum+=*p; }
  return sum;
}
