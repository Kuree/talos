#include "sv_vpi_user.h"
#include <stdio.h>

static const char *type_name(int type) {
  return type == vpiNet ? "vpiNet" : type == vpiRange ? "vpiRange" : type == vpiModule ? "vpiModule" : "other";
}

static void show(const char *what, int type, vpiHandle reference) {
  vpiHandle it = vpi_iterate(type, reference);
  if (!it) {
    printf("null iterator of %s\n", what);
    return;
  }
  vpiHandle use = vpi_handle(vpiUse, it);
  printf("%s of %s:", vpi_get_str(vpiType, it), what);
  printf(" type=%s use=%s", type_name(vpi_get(vpiIteratorType, it)), use ? vpi_get_str(vpiName, use) : "null");
  if (reference)
    printf(" same=%d", use ? vpi_compare_objects(use, reference) : 0);
  /* The iterator still works after these queries. */
  vpiHandle first = vpi_scan(it);
  if (type == vpiRange)
    printf(" first=%s\n", first ? vpi_get_str(vpiType, first) : "null");
  else
    printf(" first=%s\n", first ? vpi_get_str(vpiName, first) : "null");
}

void probe(void) {
  show("nets", vpiNet, vpi_handle_by_name("top", 0));
  show("ranges", vpiRange, vpi_handle_by_name("top.v", 0));
  show("modules", vpiModule, NULL);
}
