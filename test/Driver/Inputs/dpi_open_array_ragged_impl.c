#include "svdpi.h"

int edit(const svOpenArrayHandle rows) {
  if (svDimensions(rows) != 3 || svHigh(rows, 1) != 2 || svGetArrayPtr(rows) ||
      svSizeOfArray(rows) || svGetArrElemPtr3(rows, 1, 0, 0) ||
      svGetArrElemPtr3(rows, 2, 2, 0) || svGetArrElemPtr3(rows, 1, 1, 2))
    return 0;
  svLogicVecVal a = {0, 0}, b = {0, 0};
  svGetLogicArrElem3VecVal(&a, rows, 1, 1, 0);
  svGetLogicArrElemVecVal(&b, rows, 2, 0, 0);
  svPutLogicArrElem3VecVal(rows, &b, 1, 1, 0);
  svPutLogicArrElemVecVal(rows, &a, 2, 0, 0);
  return a.aval == 0xf0 && a.bval == 0xff && b.aval == 0xfe && b.bval == 0;
}
