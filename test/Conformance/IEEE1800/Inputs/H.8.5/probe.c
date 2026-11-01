#include "svdpi.h"
extern int take(const svLogicVecVal*);
int f(void){svLogicVecVal v={5,0};return take(&v);}
