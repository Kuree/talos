#include "sv_vpi_user.h"
#include <stdio.h>
static int count(int relation, vpiHandle h) {
  int n = 0;
  vpiHandle it = vpi_iterate(relation, h);
  while (it && vpi_scan(it))
    n++;
  return n;
}
void probe(void) {
  vpiHandle b = vpi_handle_by_name("top.b", 0);
  printf("instance type=%s", vpi_get_str(vpiType, b));
  printf(" name=%s", vpi_get_str(vpiName, b));
  printf(" def=%s", vpi_get_str(vpiDefName, b));
  printf(" full=%s", vpi_get_str(vpiFullName, b));
  printf(" index=%s\n", vpi_handle(vpiIndex, b) ? "set" : "null");
  printf("modports=%d contassigns=%d processes=%d children=%d\n", count(vpiModport, b), count(vpiContAssign, b),
         count(vpiProcess, b), count(vpiInterface, b));
  vpiHandle element = vpi_handle_by_name("top.arr[1]", 0);
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(vpi_handle(vpiIndex, element), &v);
  printf("element full=%s index=%d\n", vpi_get_str(vpiFullName, element), v.value.integer);
  vpi_get_value(vpi_handle_by_name("top.b.gnt", 0), &v);
  printf("value gnt=%d\n", v.value.integer);
}
