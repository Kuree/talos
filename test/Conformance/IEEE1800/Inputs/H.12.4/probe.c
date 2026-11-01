#include "svdpi.h"
int f(const svOpenArrayHandle a){int*p=svGetArrayPtr(a);return !p || (svSizeOfArray(a)==2*sizeof(int) && p[0]==4 && p[1]==5);}
