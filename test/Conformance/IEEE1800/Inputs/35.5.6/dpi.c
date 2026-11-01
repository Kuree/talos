#include "svdpi.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
void c35_wide(svBitVecVal *v) { v[0]=0x89abcdefu; v[1]=0x12345678u; v[2]=1u; }
typedef struct { int i; double r; } c35_pair;
