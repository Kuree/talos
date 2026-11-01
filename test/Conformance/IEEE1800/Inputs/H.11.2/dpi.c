#include "svdpi.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef struct { int i; double r; } c35_pair;
int c35_open_matrix(const svOpenArrayHandle a) {
  if(svDimensions(a)!=2 || svLeft(a,1)!=2 || svRight(a,1)!=1 || svLeft(a,2)!=-1 || svRight(a,2)!=1) return -100;
  int sum=0; for(int i=1;i<=2;++i) for(int j=-1;j<=1;++j) { int *p=svGetArrElemPtr2(a,i,j); if(!p)return -101; sum+=*p; } return sum;
}
