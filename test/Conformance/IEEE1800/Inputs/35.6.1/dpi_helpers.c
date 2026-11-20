#include "svdpi.h"

void edit(const svOpenArrayHandle a) {
  int *first = svGetArrElemPtr1(a, 0);
  int *last = svGetArrElemPtr1(a, 2);
  if (first && last) {
    int saved = *first;
    *first = *last;
    *last = saved;
  }
}
