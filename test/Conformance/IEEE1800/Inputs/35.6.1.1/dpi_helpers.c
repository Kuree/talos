#include "svdpi.h"

int exchange(const svOpenArrayHandle a, const svOpenArrayHandle b) {
  svLogicVecVal logic = {0, 0};
  svBitVecVal bits = 0;
  svGetLogicArrElem1VecVal(&logic, a, 0);
  svGetBitArrElem1VecVal(&bits, b, 0);
  if (svLeft(a, 0) != 5 || svLeft(b, 0) != 7 || svRight(b, 0) != 0 ||
      logic.aval != 0x31 || logic.bval != 0x14 || bits != 0x25)
    return 0;
  logic.aval = 7;
  logic.bval = 5;
  bits = 0x39;
  svPutLogicArrElem1VecVal(a, &logic, 0);
  svPutBitArrElem1VecVal(b, &bits, 0);
  return 1;
}
