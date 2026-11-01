#include "svdpi.h"
int legacy(svBitPackedArrRef a){svBitVec32 v;svGetBitVec32(&v,a,8);return v;}
