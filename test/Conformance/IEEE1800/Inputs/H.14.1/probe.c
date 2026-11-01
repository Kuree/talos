#include "svdpi.h"
static void (* volatile target)(void)=(void(*)(void))svDpiVersion;
int probe(void){return target!=0;}
