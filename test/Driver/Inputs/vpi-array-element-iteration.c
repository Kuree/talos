#include "sv_vpi_user.h"
#include <stdio.h>

static void report(const char *what) {
  s_vpi_error_info info;
  if (vpi_chk_error(&info) && info.message)
    printf("  %s: %s\n", what, info.message);
}

// Prints every object an element iteration of the array returns.
static void iterate(PLI_INT32 selector, const char *selectorName,
                    vpiHandle array) {
  vpiHandle iterator = vpi_iterate(selector, array);
  report(selectorName);
  printf("  %s:", selectorName);
  if (!iterator)
    printf(" none");
  for (vpiHandle element; iterator && (element = vpi_scan(iterator));) {
    s_vpi_value value = {vpiIntVal, {0}};
    vpi_get_value(element, &value);
    printf(" %s", vpi_get_str(vpiFullName, element));
    printf("=%s:%d", vpi_get_str(vpiType, element), value.value.integer);
  }
  printf("\n");
}

static void describe(const char *name) {
  vpiHandle array = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
  printf("%s\n", name);
  iterate(vpiReg, "vpiReg", array);
  iterate(vpiMemoryWord, "vpiMemoryWord", array);
  iterate(vpiVarSelect, "vpiVarSelect", array);
}

void probe(void) {
  describe("top.ints");
  describe("top.mem");
  describe("top.grid");
  describe("top.grid[1]");
  describe("top.fa");
}
