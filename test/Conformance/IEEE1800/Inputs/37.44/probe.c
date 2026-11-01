#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static vpiHandle parent;
static int count(vpiHandle it) {
  int n = 0;
  if (it)
    while (vpi_scan(it))
      n++;
  return n;
}
void probe(int phase) {
  vpiHandle e = vpi_handle_by_name("top.e", 0);
  vpiHandle t, first = 0, first_parent = 0, it = vpi_iterate(vpiWaitingProcesses, e);
  int waiters = 0;
  if (it)
    while ((t = vpi_scan(it))) {
      vpiHandle p = vpi_handle(vpiParent, t);
      printf("waiter type=%s active=%d", str(vpiType, t), vpi_get(vpiActive, t));
      printf(" origin=%s", str(vpiType, vpi_handle(vpiOrigin, t)));
      printf(" parent=%s parent_active=%d\n", str(vpiType, p), p ? vpi_get(vpiActive, p) : -1);
      if (first)
        printf("distinct=%d same_parent=%d\n", !vpi_compare_objects(first, t), vpi_compare_objects(first_parent, p));
      else {
        first = t;
        first_parent = p;
      }
      waiters++;
    }
  if (first_parent)
    parent = first_parent;
  printf("phase=%d waiters=%d children=%d", phase, waiters, parent ? count(vpi_iterate(vpiThread, parent)) : -1);
  printf(" root_parent=%s\n", str(vpiType, parent ? vpi_handle(vpiParent, parent) : 0));
}
