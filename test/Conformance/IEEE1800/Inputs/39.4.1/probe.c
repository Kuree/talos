#include "sv_vpi_user.h"
#include <stdio.h>
static struct { int reason, control; char *name; } table[] = {
    {cbAssertionSysOff, vpiAssertionSysOff, "off"},
    {cbAssertionSysOn, vpiAssertionSysOn, "on"},
    {cbAssertionSysLock, vpiAssertionSysLock, "lock"},
    {cbAssertionSysUnlock, vpiAssertionSysUnlock, "unlock"},
    {cbAssertionSysKill, vpiAssertionSysKill, "kill"},
    {cbAssertionSysReset, vpiAssertionSysReset, "reset"},
    {cbAssertionSysEnd, vpiAssertionSysEnd, "end"},
};
enum { count = sizeof table / sizeof table[0] };
static PLI_INT32 fired(p_cb_data cb) {
  int matches = 0;
  for (int i = 0; i < count; i++)
    matches += table[i].reason == cb->reason && table[i].name == cb->user_data;
  printf("fired %s reason=%d\n", cb->user_data, matches);
  return 0;
}
void probe(void) {
  int registered = 0;
  for (int i = 0; i < count; i++) {
    s_cb_data cb = {.reason = table[i].reason, .cb_rtn = fired, .user_data = table[i].name};
    registered += vpi_register_cb(&cb) != 0;
  }
  printf("registered=%d\n", registered);
  for (int i = 0; i < count; i++)
    vpi_control(table[i].control, NULL);
}
