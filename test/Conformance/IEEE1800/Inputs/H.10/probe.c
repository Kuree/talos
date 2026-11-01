#include "svdpi.h"
int word(const svBitVecVal *v, int i) { return i ? (int)(v[1] & 0xff) : (int)v[0]; }
