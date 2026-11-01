#include "sv_vpi_user.h"
static void (* volatile target)(void)=(void(*)(void))vpi_register_assertion_cb;
int probe(void){return target!=0;}
