#include "sv_vpi_user.h"
#include <stdio.h>
void off_u(void) { printf("off u=%d\n", vpi_control(vpiAssertionSysOff, vpi_handle_by_name("top.u", 0))); }
void off_all(void) { printf("off all=%d\n", vpi_control(vpiAssertionSysOff, NULL)); }
void on_all(void) { printf("on all=%d\n", vpi_control(vpiAssertionSysOn, NULL)); }
