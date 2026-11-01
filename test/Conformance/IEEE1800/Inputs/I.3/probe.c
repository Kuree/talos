#include "svdpi.h"
int getb(const svBitVecVal *v, int i) { return svGetBitselBit(v, i); }
int part(const svBitVecVal *v) { svBitVecVal d[1]; svGetPartselBit(d, v, 28, 8); return (int)(d[0] & 0xff); }
void putb(const svBitVecVal *v, svBitVecVal *y) { y[0] = v[0]; y[1] = v[1]; svPutBitselBit(y, 2, 1); }
int lgb(const svLogicVecVal *v, int i) { return svGetBitselLogic(v, i); }
