#include "sv_vpi_user.h"
#include <stdio.h>
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static vpiHandle head(const char *path, const char *label) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)path, 0);
  printf("%s type=%s", label, vpi_get_str(vpiType, h));
  printf(" packed=%d tagged=%d", vpi_get(vpiPacked, h), vpi_get(vpiTagged, h));
  return h;
}
static void members(vpiHandle h) {
  vpiHandle it = vpi_iterate(vpiMember, h);
  for (vpiHandle m; it && (m = vpi_scan(it));) {
    printf(" member %s=%d", vpi_get_str(vpiName, m), value(m));
    printf(" parent=%s", vpi_get_str(vpiFullName, vpi_handle(vpiParent, m)));
  }
  printf("\n");
}
void probe(void) {
  // 37.17 detail 9: an unpacked struct's size is its field count, a packed one's its bits.
  vpiHandle su = head("top.su", "su");
  printf(" size=%d", vpi_get(vpiSize, su));
  members(su);
  // Detail 1: vpi_get_value() cannot access an entire unpacked structure.
  s_vpi_value whole = {.format = vpiIntVal};
  s_vpi_error_info info;
  vpi_get_value(su, &whole);
  printf("whole unpacked read error=%d\n", vpi_chk_error(&info) != 0);
  vpiHandle sp = head("top.sp", "sp");
  printf(" size=%d value=%d", vpi_get(vpiSize, sp), value(sp));
  members(sp);
  vpiHandle un = head("top.un", "un");
  printf(" size=%d value=%d", vpi_get(vpiSize, un), value(un));
  members(un);
  head("top.ta", "ta");
  printf("\n");
  s_vpi_value put = {.format = vpiIntVal, .value = {.integer = 9}};
  vpi_put_value(vpi_handle_by_name("top.su.a", 0), &put, 0, vpiNoDelay);
}
