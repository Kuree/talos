#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
void probe(void) {
  // 37.10 detail 4 and 37.20 detail 1: the vpiMemory iteration returns array variable objects.
  vpiHandle m = vpi_scan(vpi_iterate(vpiMemory, vpi_handle_by_name("top", 0)));
  printf("memory reg-array=%d name=%s", vpi_get(vpiType, m) == vpiRegArray, vpi_get_str(vpiName, m));
  printf(" is-memory=%d size=%d left=%d right=%d\n", vpi_get(vpiIsMemory, m), vpi_get(vpiSize, m),
         value(vpi_handle(vpiLeftRange, m)), value(vpi_handle(vpiRightRange, m)));
  int n = 0, regs = 0;
  vpiHandle it = vpi_iterate(vpiMemoryWord, m);
  for (vpiHandle w; it && (w = vpi_scan(it)); n++)
    regs += vpi_get(vpiType, w) == vpiReg;
  printf("words=%d reg=%d\n", n, regs == n && n > 0);
  vpiHandle w = vpi_handle_by_index(m, 2);
  printf("word full=%s", vpi_get_str(vpiFullName, w));
  printf(" left=%d right=%d size=%d index=%d", value(vpi_handle(vpiLeftRange, w)), value(vpi_handle(vpiRightRange, w)),
         vpi_get(vpiSize, w), value(vpi_handle(vpiIndex, w)));
  printf(" parent=%s value=%d\n", vpi_get_str(vpiFullName, vpi_handle(vpiParent, w)), value(w));
  s_vpi_value put = {.format = vpiIntVal, .value = {.integer = 66}};
  vpi_put_value(vpi_handle_by_index(m, 3), &put, 0, vpiNoDelay);
}
