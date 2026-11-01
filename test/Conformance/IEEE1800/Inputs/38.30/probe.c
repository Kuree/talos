#include "sv_vpi_user.h"
int probe(void) { return vpi_printf("n=%d s=%s x=%x f=%5.2f\n", 7, "abc", 255, 1.5); }
