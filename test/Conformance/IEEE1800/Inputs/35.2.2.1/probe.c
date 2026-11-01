#include "svdpi.h"
int lv(const svLogicVecVal *x) { return ((x->aval & 0xf) << 4) | (x->bval & 0xf); }
int bt(svBit b) { return b ? 10 : 20; }
void out4(svLogicVecVal *y) { y->aval = 0x6; y->bval = 0x3; }   /* 4'b01xz */
