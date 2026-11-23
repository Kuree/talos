#include "sv_vpi_user.h"
#include <stdio.h>

static void report(const char *what) {
  s_vpi_error_info info;
  printf("  %s: %s\n", what,
         vpi_chk_error(&info) && info.message ? info.message : "ok");
}

// Prints the array properties that the declaration and the current contents
// determine, then tries to select an element.
static vpiHandle describe(const char *name) {
  vpiHandle array = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
  printf("%s type=%s arraytype=%d memory=%d\n", name,
         vpi_get_str(vpiType, array), vpi_get(vpiArrayType, array),
         vpi_get(vpiIsMemory, array));
  printf("  size=%d\n", vpi_get(vpiSize, array));
  report("size");
  vpiHandle element = vpi_handle_by_index(array, 0);
  printf("  element %s\n", element ? "found" : "none");
  report("by_index");
  return array;
}

// Containers also refuse element iteration and element names.
static void describeContainer(const char *name, const char *elementName) {
  vpiHandle elements = vpi_iterate(vpiReg, describe(name));
  printf("  elements %s\n", elements ? "found" : "none");
  report("iterate");
  vpiHandle element = vpi_handle_by_name((PLI_BYTE8 *)elementName, NULL);
  printf("  %s %s\n", elementName, element ? "found" : "none");
  report("by_name");
}

void probe(void) {
  describe("top.fixed");
  describeContainer("top.dyn", "top.dyn[0]");
  describeContainer("top.empty", "top.empty[0]");
  describeContainer("top.q", "top.q[0]");
  describeContainer("top.aa", "top.aa[0]");
  describeContainer("top.nested", "top.nested[0]");
  // A fixed array of dynamic arrays: each element is a dynamic array.
  vpiHandle fixedOfDynamic = describe("top.fa");
  vpiHandle second = vpi_handle_by_index(fixedOfDynamic, 1);
  printf("  [1] type=%s arraytype=%d size=%d\n", vpi_get_str(vpiType, second),
         vpi_get(vpiArrayType, second), vpi_get(vpiSize, second));
}
