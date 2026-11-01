#include "svdpi.h"
void query(const svOpenArrayHandle b, int *ul, int *ur, int *pl, int *pr, int *first) {
  svBitVecVal v = 0;
  *ul = svLeft(b, 1);
  *ur = svRight(b, 1);
  *pl = svLeft(b, 0);
  *pr = svRight(b, 0);
  svGetBitArrElem1VecVal(&v, b, *ul);
  *first = (int)v;
}
