#include "svdpi.h"
#include <stdio.h>

int read_rows(const svOpenArrayHandle rows) {
  puts("entered read_rows");
  // C index zero addresses formal row 3, corresponding to actual row 1.
  const int *r3 = svGetArrElemPtr2(rows, 0, 0);
  const int *r4 = svGetArrElemPtr2(rows, 1, 1);
  return svLeft(rows, 1) == 0 && svRight(rows, 1) == 1 && r3 && *r3 == 21 &&
         r4 && *r4 == 12 && !svGetArrElemPtr2(rows, 0, 1);
}

void edit_rows(const svOpenArrayHandle rows) {
  int *r3 = svGetArrElemPtr2(rows, 0, 0);
  int *r4 = svGetArrElemPtr2(rows, 1, 1);
  if (r3 && r4) {
    *r3 = 41;
    *r4 = 32;
  }
}
