#include "svdpi.h"

int edit(const svOpenArrayHandle rows) {
  int *first = svGetArrElemPtr2(rows, 0, 0);
  int *last = svGetArrElemPtr(rows, 2, 2);
  if (!first || *first != 4 || !last || *last != 13 ||
      svGetArrElemPtr2(rows, 1, 0) || svGetArrElemPtr2(rows, 0, 1) ||
      svGetArrayPtr(rows) || svSizeOfArray(rows) != 0)
    return 0;
  *first += 2;
  *last += 1;
  return 1;
}
