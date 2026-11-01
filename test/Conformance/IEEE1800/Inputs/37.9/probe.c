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
  vpiHandle p = vpi_handle_by_name("top.p", 0);
  printf("program type=%s", vpi_get_str(vpiType, p));
  printf(" name=%s", vpi_get_str(vpiName, p));
  printf(" def=%s", vpi_get_str(vpiDefName, p));
  printf(" full=%s", vpi_get_str(vpiFullName, p));
  printf(" index=%s processes=%d", vpi_handle(vpiIndex, p) ? "set" : "null", count(vpiProcess, p));
  vpiHandle clocking = vpi_handle(vpiDefaultClocking, p);
  printf(" clocking=%s\n", clocking ? vpi_get_str(vpiName, clocking) : "null");
  vpiHandle element = vpi_handle_by_name("top.pa[1]", 0);
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(vpi_handle(vpiIndex, element), &v);
  printf("element full=%s index=%d\n", vpi_get_str(vpiFullName, element), v.value.integer);
  vpi_get_value(vpi_handle_by_name("top.p.v", 0), &v);
  printf("value v=%d\n", v.value.integer);
}
