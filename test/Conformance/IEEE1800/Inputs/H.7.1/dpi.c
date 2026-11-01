#include "svdpi.h"
void query(const svOpenArrayHandle b, int *left, int *right, int *value) {
  const svBitVecVal *raw = (const svBitVecVal *)svGetArrayPtr(b);
  *left = svLeft(b, 0);
  *right = svRight(b, 0);
  *value = (int)raw[0];
}
void query2(const svOpenArrayHandle b, int *left, int *right, int *ul, int *ur, int *value) {
  svBitVecVal v = 0;
  *left = svLeft(b, 0);
  *right = svRight(b, 0);
  *ul = svLeft(b, 1);
  *ur = svRight(b, 1);
  svGetBitArrElem1VecVal(&v, b, *ul);
  *value = (int)v;
}
