#include "sv_vpi_user.h"
static void (* volatile target)(void)=(void(*)(void))vpi_chk_error;
int probe(void){return target!=0;}
