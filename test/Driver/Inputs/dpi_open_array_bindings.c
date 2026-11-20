#include "svdpi.h"

int inspect(const svOpenArrayHandle rows, const svOpenArrayHandle q) {
  const int *row = svGetArrElemPtr2(rows, 1, 1);
  int *last = svGetArrElemPtr1(q, 2);
  if (!row || !last || *last != 3)
    return 0;
  *last = *row;
  return svLeft(rows, 1) == 1 && svRight(rows, 1) == 0 &&
         svLeft(rows, 2) == 0 && svRight(rows, 2) == 1;
}
