#include "svdpi.h"
int words(void) { svBitVec32 w[SV_CANONICAL_SIZE(33)]; return (int)(sizeof(w) / sizeof(w[0])); }
