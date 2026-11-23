#include "sv_vpi_user.h"
#include <stdio.h>

static void report(const char *what) {
  s_vpi_error_info info;
  printf("  %s: %s\n", what,
         vpi_chk_error(&info) && info.message ? info.message : "ok");
}

// Prints an object's bounds as [left:right], or [] when it has none.
static void printBounds(vpiHandle object) {
  vpiHandle left = vpi_handle(vpiLeftRange, object);
  vpiHandle right = vpi_handle(vpiRightRange, object);
  if (!left || !right) {
    printf(" []");
    return;
  }
  s_vpi_value value = {vpiIntVal, {0}};
  vpi_get_value(left, &value);
  int leftBound = value.value.integer;
  vpi_get_value(right, &value);
  printf(" [%d:%d]", leftBound, value.value.integer);
}

// Prints the array's leftmost bounds, then each range and its size.
static void printRanges(vpiHandle array) {
  printf("  bounds");
  printBounds(array);
  printf(" ranges");
  vpiHandle ranges = vpi_iterate(vpiRange, array);
  for (vpiHandle range; ranges && (range = vpi_scan(ranges));) {
    printBounds(range);
    printf("/%d", vpi_get(vpiSize, range));
  }
  printf("\n");
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
  printRanges(array);
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

// The first range of dyn, kept until resized() runs.
static vpiHandle dynRange;

void probe(void) {
  dynRange = vpi_scan(
      vpi_iterate(vpiRange, vpi_handle_by_name((PLI_BYTE8 *)"top.dyn", NULL)));
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
  printRanges(second);
}

// After the design resizes its arrays, sizes and ranges follow the new
// contents, including the range handle obtained before the resize.
void resized(void) {
  static const char *names[] = {"top.dyn", "top.q", "top.aa"};
  for (unsigned i = 0; i != sizeof(names) / sizeof(names[0]); ++i) {
    vpiHandle array = vpi_handle_by_name((PLI_BYTE8 *)names[i], NULL);
    printf("%s size=%d\n", names[i], vpi_get(vpiSize, array));
    printRanges(array);
  }
  printf("kept dyn range");
  printBounds(dynRange);
  printf("/%d\n", vpi_get(vpiSize, dynRange));
}
