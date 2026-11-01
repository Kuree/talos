#include "sv_vpi_user.h"
static void (* volatile target)(void)=(void(*)(void))vpi_get_systf_info;
int probe(void){return target!=0;}
