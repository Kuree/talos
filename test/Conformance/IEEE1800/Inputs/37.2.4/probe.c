#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static vpiHandle first, second, member;
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
void create_handles(void) {
  first = vpi_handle_by_name("top.n", 0);
  second = vpi_handle_by_name("top.n", 0);
  printf("created n=%d same=%d\n", value(first), vpi_compare_objects(first, second));
}
void read_later(void) {
  if (first)
    printf("later n=%d\n", value(first));
  else
    printf("released first, second n=%d\n", value(second));
}
void release_first(void) {
  vpi_release_handle(first);
  first = 0;
}
// A class object is a transient object (37.3.7): reach the data member of the live object.
void grab_member(void) {
  vpiHandle object = vpi_handle(vpiClassObj, vpi_handle_by_name("top.owner", 0));
  vpiHandle it = object ? vpi_iterate(vpiVariables, object) : 0;
  for (vpiHandle h; it && (h = vpi_scan(it));)
    if (!strcmp(vpi_get_str(vpiName, h), "v"))
      member = h;
  if (member)
    printf("object member v=%d dynamic=%d\n", value(member), vpi_get(vpiAllocScheme, member) == vpiDynamicScheme);
  else
    printf("object member null\n");
}
void read_member(void) {
  if (member)
    printf("object still alive v=%d\n", value(member));
  else
    printf("object still alive null\n");
}
