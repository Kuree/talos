#include "svdpi.h"

int inspect(const svOpenArrayHandle rows, const svOpenArrayHandle result) {
  const int *first = svGetArrElemPtr2(rows, 3, 0);
  const int *last = svGetArrElemPtr2(rows, 2, 1);
  int *out_first = svGetArrElemPtr2(result, 3, 0);
  int *out_last = svGetArrElemPtr2(result, 2, 1);
  if (!first || !last || !out_first || !out_last ||
      svGetArrElemPtr2(result, 3, 1))
    return 0;
  *out_first = *first;
  *out_last = *last;
  return svDimensions(rows) == 2 && svLeft(rows, 1) == 3 &&
         svRight(rows, 1) == 2 && svLeft(rows, 2) == 0 &&
         svRight(rows, 2) == 1 && *first == 11 && *last == 22;
}
