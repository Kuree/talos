#include "sv_vpi_user.h"
#include <stdio.h>
static PLI_INT64 id(const char *name) {
  return vpi_get64(vpiObjId, vpi_handle_by_name((PLI_BYTE8 *)name, 0));
}
void first(void) {
  // 37.33 details 1 and 2: a class var's vpiObjId names the object it references, 0 if none.
  PLI_INT64 a = id("top.a");
  printf("null=%lld live=%d alias_same=%d other_differs=%d\n", (long long)id("top.none"), a != 0,
         a == id("top.b"), a != id("top.c"));
}
void second(void) {
  vpiHandle object = vpi_handle(vpiClassObj, vpi_handle_by_name("top.a", 0));
  printf("retargeted=%d object_same=%d\n", id("top.a") == id("top.c"),
         vpi_get64(vpiObjId, object) == id("top.c"));
  PLI_INT64 wrong = id("top.n");
  printf("not_a_class=%lld error=%d\n", (long long)wrong, vpi_chk_error(NULL) != 0);
}
