#include "svdpi.h"

void edit(const svOpenArrayHandle a) {
  svLogicVecVal first[2], second[2];
  svGetLogicArrElemVecVal(first, a, 0);
  svGetLogicArrElem1VecVal(second, a, 1);
  svPutLogicArrElem1VecVal(a, second, 0);
  svPutLogicArrElemVecVal(a, first, 1);
}
