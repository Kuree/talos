#include "svdpi_src.h"
int words(void) { SV_BIT_PACKED_ARRAY(33, w); return (int)(sizeof(w) / sizeof(w[0])); }
