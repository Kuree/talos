#include "svdpi.h"
int enc(svLogic b) { return b; }
int bits(const svBitVecVal *v, int word) { return word ? (int)(v[1] & 0xff) : (int)v[0]; }
