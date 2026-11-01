#include "sv_vpi_user.h"
#include <stdio.h>

static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}

static void scope(const char *what, vpiHandle s) {
  if (!s) {
    printf("%s null\n", what);
    return;
  }
  printf("%s %s", what, vpi_get_str(vpiType, s));
  printf(" full=%s", vpi_get_str(vpiFullName, s));
}

void probe(void) {
  vpiHandle array = vpi_handle_by_name("top.gb", 0);
  if (array) {
    printf("array %s", vpi_get_str(vpiType, array));
    printf(" name=%s", vpi_get_str(vpiName, array));
    printf(" full=%s", vpi_get_str(vpiFullName, array));
    printf(" size=%d\n", vpi_get(vpiSize, array));
  } else
    printf("array null\n");

  vpiHandle e = array ? vpi_handle_by_index(array, 1) : NULL;
  scope("element", e);
  if (e) {
    vpiHandle index = vpi_handle(vpiIndex, e), g = vpi_scan(vpi_iterate(vpiParameter, e));
    vpiHandle v = vpi_scan(vpi_iterate(vpiVariables, e));
    printf(" index=%d", index ? value(index) : -1);
    printf(" member=%d implicit=%d", vpi_get(vpiArrayMember, e), vpi_get(vpiImplicitDecl, e));
    printf(" %s=", g ? vpi_get_str(vpiName, g) : "null");
    printf("%d", g ? value(g) : -1);
    printf(" %s=", v ? vpi_get_str(vpiName, v) : "null");
    printf("%d\n", v ? value(v) : -1);
  }

  vpiHandle named = vpi_handle_by_name("top.nb", 0);
  scope("named", named);
  if (named)
    printf(" member=%d implicit=%d\n", vpi_get(vpiArrayMember, named), vpi_get(vpiImplicitDecl, named));

  /* An unnamed generate block is genblk<n> for the n-th generate construct of its scope (27.6). */
  vpiHandle unnamed = vpi_handle_by_name("top.genblk3", 0);
  scope("unnamed", unnamed);
  if (unnamed)
    printf(" member=%d implicit=%d\n", vpi_get(vpiArrayMember, unnamed), vpi_get(vpiImplicitDecl, unnamed));
}
