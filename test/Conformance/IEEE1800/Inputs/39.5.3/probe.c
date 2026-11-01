#include "sv_vpi_user.h"
static void (* volatile target)(void)=(void(*)(void))vpi_get;
int probe(void){return target!=0;}
