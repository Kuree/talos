#include "sv_vpi_user.h"
static void (* volatile target)(void)=(void(*)(void))vpi_mcd_vprintf;
int probe(void){return target!=0;}
