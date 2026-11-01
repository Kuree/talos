#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
void describe(void) {
  vpiHandle e = vpi_handle_by_name("top.e", 0);
  printf("event type=%s", vpi_get_str(vpiType, e));
  printf(" name=%s", vpi_get_str(vpiName, e));
  printf(" full=%s", vpi_get_str(vpiFullName, e));
  printf(" auto=%d other-scheme=%d array-member=%d", vpi_get(vpiAutomatic, e),
         vpi_get(vpiAllocScheme, e) == vpiOtherScheme, vpi_get(vpiArrayMember, e));
  // Detail 2: not part of an array, so the vpiIndex iteration is NULL.
  printf(" index=%s", vpi_iterate(vpiIndex, e) ? "set" : "null");
  vpiHandle type = vpi_handle(vpiTypespec, e);
  printf(" typespec=%s", type ? vpi_get_str(vpiType, type) : "null");
  // Detail 1: the always block is suspended at @e.
  int waiting = 0;
  vpiHandle it = vpi_iterate(vpiWaitingProcesses, e);
  while (it && vpi_scan(it))
    waiting++;
  printf(" waiting=%d\n", waiting);
}
void fire(void) {
  // 38.34: a named event toggles and needs no value, so value_p may be NULL.
  vpi_put_value(vpi_handle_by_name("top.e", 0), 0, 0, vpiNoDelay);
}
void describe_array(void) {
  vpiHandle a = vpi_handle_by_name("top.ea", 0);
  vpiHandle element = vpi_handle_by_index(a, 1);
  printf("array type=%s", vpi_get_str(vpiType, a));
  printf(" full=%s", vpi_get_str(vpiFullName, a));
  printf(" element=%s", vpi_get_str(vpiFullName, element));
  vpiHandle index = vpi_scan(vpi_iterate(vpiIndex, element));
  printf(" array-member=%d index=%d\n", vpi_get(vpiArrayMember, element), value(index));
  vpi_put_value(element, 0, 0, vpiNoDelay);
}
