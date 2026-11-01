#include "svdpi.h"
int f(void){svLogicVecVal v={0,0};svPutBitselLogic(&v,2,sv_x);return svGetBitselLogic(&v,2)==sv_x;}
