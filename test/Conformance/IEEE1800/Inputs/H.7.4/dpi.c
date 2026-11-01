#include "svdpi.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
int c35_scalar(int i, signed char b, short s, long long l, double r, float sr, svBit bit, svLogic logic) {
  return i==17 && b==-3 && s==-1200 && l==-10000000000LL && r==2.5 && sr==1.25f && bit==sv_1 && logic==sv_z;
}
typedef struct { int i; double r; } c35_pair;
