#include "svdpi.h"
void get(const svLogicVecVal *v, int *a0, int *b0, int *a1, int *b1) {
  *a0 = v[0].aval; *b0 = v[0].bval; *a1 = v[1].aval & 0xf; *b1 = v[1].bval & 0xf;
}
