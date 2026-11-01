#include "svdpi.h"
int en(int x) { return x * 10; }
void ti(const svLogicVecVal *i, const svLogicVecVal *t, int *ia, int *ib, int *t0, int *t1, int *tb1) {
  *ia = i->aval; *ib = i->bval; *t0 = t[0].aval; *t1 = t[1].aval; *tb1 = t[1].bval;
}
