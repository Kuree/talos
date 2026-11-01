#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static const char *nettype(vpiHandle h) {
  int t = vpi_get(vpiNetType, h);
  return t == vpiWire ? "vpiWire" : t == vpiWand ? "vpiWand" : "other";
}
void first(void) {
  vpiHandle w = vpi_handle_by_name("top.w", 0);
  printf("w type=%s", vpi_get_str(vpiType, w));
  printf(" size=%d nettype=%s scalar=%d vector=%d implicit=%d value=%d\n", vpi_get(vpiSize, w), nettype(w),
         vpi_get(vpiScalar, w), vpi_get(vpiVector, w), vpi_get(vpiImplicitDecl, w), value(w));
}
void second(void) {
  vpiHandle w = vpi_handle_by_name("top.w", 0);
  printf("w value=%d\n", value(w));
  int n = 0;
  vpiHandle it = vpi_iterate(vpiBit, w), bit3 = 0;
  for (vpiHandle b; it && (b = vpi_scan(it)); n++)
    if (value(vpi_handle(vpiIndex, b)) == 3)
      bit3 = b;
  printf("bits=%d", n);
  printf(" bit type=%s", vpi_get_str(vpiType, bit3));
  printf(" full=%s", vpi_get_str(vpiFullName, bit3));
  printf(" parent=%s", vpi_get_str(vpiFullName, vpi_handle(vpiParent, bit3)));
  printf(" index=%d value=%d\n", value(vpi_handle(vpiIndex, bit3)), value(bit3));
  vpiHandle both = vpi_handle_by_name("top.both", 0);
  printf("wired and nettype=%s value=%d\n", nettype(both), value(both));
  vpiHandle arr = vpi_handle_by_name("top.arr", 0);
  vpiHandle member = vpi_handle_by_index(arr, 1);
  printf("array type=%s size=%d", vpi_get_str(vpiType, arr), vpi_get(vpiSize, arr));
  printf(" member=%d %s value=%d\n", vpi_get(vpiArrayMember, member), vpi_get_str(vpiFullName, member), value(member));
  // Detail 9: an implicit net reports line 0.
  vpiHandle made = vpi_handle_by_name("top.made_up", 0);
  printf("implicit type=%s implicit=%d line=%d value=%d\n", vpi_get_str(vpiType, made), vpi_get(vpiImplicitDecl, made),
         vpi_get(vpiLineNo, made), value(made));
}
