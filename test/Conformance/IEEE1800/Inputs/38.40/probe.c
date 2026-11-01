#include "sv_vpi_user.h"
int probe(void){vpiHandle i=vpi_iterate(vpiModule,0),h=i?vpi_scan(i):0;return h&&vpi_get(vpiType,h)==vpiModule;}
