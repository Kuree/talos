#include "svdpi.h"
void q(const svOpenArrayHandle a, int *l, int *r, int *lo, int *hi, int *inc, int *sz, int *dims, int *sum) {
  int s = 0;
  *l = svLeft(a, 1); *r = svRight(a, 1); *lo = svLow(a, 1); *hi = svHigh(a, 1);
  *inc = svIncrement(a, 1); *sz = svSize(a, 1); *dims = svDimensions(a);
  for (int i = *lo; i <= *hi; i++) s += *(int *)svGetArrElemPtr1(a, i);
  *sum = s;
}
