#include "sv_vpi_user.h"
static void (* volatile target)(void)=(void(*)(void))vpi_handle_multi;
int probe(void){return target!=0;}
